"""
Voice token server — public HTTPS endpoint (Cloud Run).

The iOS app calls GET /token?room=...&identity=... and gets back the LiveKit
server URL plus a short-lived join token. The LiveKit API secret stays
server-side. Deployed to Cloud Run via CI (.github/workflows/deploy.yml), so the
phone reaches it over normal internet on any network — no Mac / local-network
dependency.

Only needs livekit-api + fastapi + uvicorn (NOT livekit-agents), so it shares
none of the agent's dependency conflicts.
"""

import json
import os
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from livekit import api

LIVEKIT_URL = os.environ["LIVEKIT_URL"]
LIVEKIT_API_KEY = os.environ["LIVEKIT_API_KEY"]
LIVEKIT_API_SECRET = os.environ["LIVEKIT_API_SECRET"]

# Supabase (read-only use here) so the app can show its own nutrition data WITHOUT
# needing a live voice session. Same keys the agent uses; stay server-side.
SUPABASE_URL = (os.environ.get("SUPABASE_URL") or "").rstrip("/")
SUPABASE_KEY = os.environ.get("SUPABASE_SERVICE_KEY") or ""

NUTRITION_QUESTIONS = [
    "Am I eating enough protein + total food to build lean mass while training? "
    "(lean mass is my biggest WHOOP-age driver; the plan reads light.)",
    "Short sleep (~5:41) — should meal timing (late dinners, caffeine, before-bed) "
    "change to help it?",
    "Avoid-list alternates: is all no-added-sugar fine? Are no-added-sugar millet "
    "pancakes OK vs maida? (swap refined→millet, sugar→no-added-sugar, fried→air-fried.)",
]

app = FastAPI(title="Invisible Health — voice token server")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/health")
def health():
    return {"ok": True}


@app.get("/status")
def status():
    """Runtime diagnosis reachable from anywhere (issue #15) — so 'coach went
    silent' can be traced from a phone/cloud session without opening a Mac. Checks
    the usual culprits: OpenAI billing/quota and Supabase."""
    out = {"token_server": "ok"}
    okey = os.environ.get("OPENAI_API_KEY")
    if okey:
        try:
            req = urllib.request.Request(
                "https://api.openai.com/v1/models",
                headers={"Authorization": f"Bearer {okey}"})
            with urllib.request.urlopen(req, timeout=10) as r:
                out["openai"] = "ok" if r.status == 200 else f"http {r.status}"
        except urllib.error.HTTPError as e:
            body = ""
            try:
                body = e.read().decode()[:200]
            except Exception:
                pass
            if e.code == 429 or "insufficient_quota" in body:
                out["openai"] = "⚠️ QUOTA/BILLING problem (top up OpenAI credits)"
            elif e.code == 401:
                out["openai"] = "⚠️ AUTH problem (bad/rotated OPENAI_API_KEY)"
            else:
                out["openai"] = f"http {e.code}: {body[:80]}"
        except Exception as e:
            out["openai"] = f"error: {e}"
    else:
        out["openai"] = "no key on token server"
    if SUPABASE_URL and SUPABASE_KEY:
        try:
            req = urllib.request.Request(
                f"{SUPABASE_URL}/rest/v1/nutrition_log?select=id&limit=1",
                headers={"apikey": SUPABASE_KEY, "Authorization": f"Bearer {SUPABASE_KEY}"})
            with urllib.request.urlopen(req, timeout=10) as r:
                out["supabase"] = "ok" if r.status < 300 else f"http {r.status}"
        except Exception as e:
            out["supabase"] = f"error: {e}"
    return out


def _fetch_meals(user_id: str, days: int) -> list:
    """Read the user's logged meals from Supabase (server-side, service key)."""
    if not (SUPABASE_URL and SUPABASE_KEY):
        return []
    since = (datetime.now(timezone.utc) - timedelta(days=days)).isoformat()
    qs = urllib.parse.urlencode({
        "user_id": f"eq.{user_id}", "logged_at": f"gte.{since}",
        "order": "logged_at.asc"})
    req = urllib.request.Request(
        f"{SUPABASE_URL}/rest/v1/nutrition_log?{qs}",
        headers={"apikey": SUPABASE_KEY, "Authorization": f"Bearer {SUPABASE_KEY}"})
    with urllib.request.urlopen(req, timeout=10) as r:
        return json.loads(r.read().decode())


@app.get("/nutrition")
def nutrition(user_id: str = "ishwar"):
    """What the Nutrition tab shows — today's logged meals + the 7-day summary,
    read straight from the database so the app never needs the coach/voice to
    refresh. Mirrors the agent's weekly-summary shape."""
    try:
        meals = _fetch_meals(user_id, 7)
    except Exception:
        meals = []
    by_day, watch, today = {}, [], []
    protein_hits = flagged = 0
    try:
        from zoneinfo import ZoneInfo
        today_key = datetime.now(ZoneInfo("Asia/Kolkata")).strftime("%Y-%m-%d")
    except Exception:
        today_key = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    for m in meals:
        fl = m.get("flags") or {}
        # Skip hypotheticals ("about to order" / "what if") — they're assessed but
        # not eaten, so they must not inflate the tab or counts (issue #4).
        if str(fl.get("eaten", "yes")).lower() == "no":
            continue
        desc = m.get("description") or "(meal)"
        # Prefer the stored local_date (absolute, timezone-correct) for grouping +
        # "today"; fall back to the raw timestamp for older rows.
        ld = m.get("local_date")
        try:
            d = datetime.fromisoformat((m.get("logged_at") or "").replace("Z", "+00:00"))
            day = d.strftime("%a %d %b")
        except Exception:
            day = ld or "recent"
        is_today = (ld == today_key) if ld else (day != "recent" and
                   d.strftime("%Y-%m-%d") == today_key)
        by_day.setdefault(day, []).append(desc)
        if str(fl.get("has_protein", "")).lower() == "yes":
            protein_hits += 1
        bad = [t for t, k in (("refined", "is_refined"), ("fried", "is_fried"),
                              ("sugar", "contains_sugar")) if str(fl.get(k, "")).lower() == "yes"]
        if str(fl.get("has_protein", "")).lower() == "no":
            bad.append("no protein")
        if bad:
            flagged += 1
            watch.append({"desc": desc, "issues": ", ".join(bad)})
        if is_today:
            today.append({"description": desc, "verdict": m.get("verdict"),
                          "meal": m.get("meal")})
    return {
        "total": len(meals), "protein_hits": protein_hits, "flagged": flagged,
        "days": [{"day": k, "items": v} for k, v in by_day.items()],
        "watch": watch, "questions": NUTRITION_QUESTIONS,
        "empty": len(meals) == 0, "today": today,
    }


@app.get("/workout")
def workout(user_id: str = "ishwar"):
    """What the Workout Plan tab shows — the most recent DECIDED workout + the
    planning discussion, read straight from planned_workouts (no voice needed)."""
    if not (SUPABASE_URL and SUPABASE_KEY):
        return {"decided": None, "discussion": None, "suggested": None}
    qs = urllib.parse.urlencode({
        "user_id": f"eq.{user_id}", "order": "created_at.desc", "limit": "1"})
    try:
        req = urllib.request.Request(
            f"{SUPABASE_URL}/rest/v1/planned_workouts?{qs}",
            headers={"apikey": SUPABASE_KEY, "Authorization": f"Bearer {SUPABASE_KEY}"})
        with urllib.request.urlopen(req, timeout=10) as r:
            rows = json.loads(r.read().decode())
    except Exception:
        rows = []
    if not rows:
        return {"decided": None, "discussion": None, "suggested": None}
    row = rows[0]
    return {"decided": row.get("decided"), "discussion": row.get("discussion"),
            "suggested": row.get("suggested"), "created_at": row.get("created_at"),
            "status": row.get("status")}


@app.get("/token")
def token(room: str = "invisible-voice", identity: str = "ios-user"):
    grant = api.VideoGrants(room_join=True, room=room, can_publish=True, can_subscribe=True)
    jwt = (
        api.AccessToken(LIVEKIT_API_KEY, LIVEKIT_API_SECRET)
        .with_identity(identity)
        .with_name(identity)
        .with_grants(grant)
        .to_jwt()
    )
    return {"serverUrl": LIVEKIT_URL, "token": jwt}
