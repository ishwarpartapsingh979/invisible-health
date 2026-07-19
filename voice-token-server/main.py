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

import asyncio
import json
import os
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone

from fastapi import FastAPI, File, Form, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from livekit import api

LIVEKIT_URL = os.environ["LIVEKIT_URL"]
LIVEKIT_API_KEY = os.environ["LIVEKIT_API_KEY"]
LIVEKIT_API_SECRET = os.environ["LIVEKIT_API_SECRET"]

# Supabase (read-only use here) so the app can show its own nutrition data WITHOUT
# needing a live voice session. Same keys the agent uses; stay server-side.
SUPABASE_URL = (os.environ.get("SUPABASE_URL") or "").rstrip("/")
SUPABASE_KEY = os.environ.get("SUPABASE_SERVICE_KEY") or ""

# Gemini vision — reads a login-gated schedule the user can only SHOW us (screenshot
# / screen-recording / PDF) into structured data. Same key the agent uses.
GEMINI_API_KEY = os.environ.get("GEMINI_API_KEY") or ""
_GEMINI = None
if GEMINI_API_KEY:
    try:
        from google import genai
        from google.genai import types as genai_types
        _GEMINI = genai.Client(api_key=GEMINI_API_KEY)
    except Exception:
        _GEMINI = None

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
                          "meal": m.get("meal"), "calories": m.get("calories"),
                          "protein_g": m.get("protein_g")})
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


# ── "Show Me": schedule extraction ────────────────────────────────────────────
# The user can only SHOW us a login-gated timetable / diet chart (Cult classes,
# society yoga, a nutritionist's PDF). The app sends a screenshot / screen-recording
# / PDF here; Gemini vision reads it into structured, time-bounded data stored per
# user in user_schedules; the coach reads it back later (get_my_schedules) instead
# of trying to browse the gated site.

def _extract_prompt(kind: str) -> str:
    today = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    if kind == "nutrition":
        what = ("a nutrition / diet chart (meal slots, foods, quantities, timings). "
                "Capture every meal slot and what to eat.")
        shape = ('{"slot": "breakfast|lunch|snack|dinner", "time": "8am or null", '
                 '"items": ["..."], "notes": "..."}')
    else:
        what = ("a fitness / class timetable (class names, days, times, maybe "
                "instructor or location). Capture every slot.")
        shape = ('{"day": "Mon|Tue|...", "time": "6:30am", "name": "HRX / Yoga", '
                 '"location": "...", "notes": "..."}')
    return (
        f"You are reading {what}\nToday is {today}. Return ONLY a JSON object "
        "(no markdown fences, no prose) of this exact shape:\n"
        '{ "title": "name if visible else null", '
        '"valid_from": "YYYY-MM-DD or null (start of the period it covers)", '
        '"valid_to": "YYYY-MM-DD or null (end; if it says this week, infer from today)", '
        f'"items": [ {shape} ] }}\n'
        "Use null for anything not visible. Extract EVERY row you can see.")


def _gemini_extract(data: bytes, mime: str, prompt: str) -> str:
    """Blocking Gemini call (image/pdf inline; video via file API + processing wait).
    Called through asyncio.to_thread so it never blocks the event loop."""
    model = "gemini-3.5-flash"
    if mime.startswith("video"):
        with tempfile.NamedTemporaryFile(suffix=".mp4", delete=False) as tf:
            tf.write(data)
            path = tf.name
        up = _GEMINI.files.upload(file=path)
        waited = 0
        while getattr(up.state, "name", "") == "PROCESSING" and waited < 240:
            time.sleep(3)
            waited += 3
            up = _GEMINI.files.get(name=up.name)
        resp = _GEMINI.models.generate_content(model=model, contents=[up, prompt])
    else:
        part = genai_types.Part.from_bytes(data=data, mime_type=mime)
        resp = _GEMINI.models.generate_content(model=model, contents=[part, prompt])
    return (resp.text or "").strip()


def _loose_json(text: str) -> dict:
    t = text.strip()
    if t.startswith("```"):
        t = t.strip("`")
        if t[:4].lower() == "json":
            t = t[4:]
    a, b = t.find("{"), t.rfind("}")
    if a != -1 and b > a:
        t = t[a:b + 1]
    return json.loads(t)


def _store_schedule(user_id, kind, title, source, extracted, raw_text, vf, vt) -> bool:
    if not (SUPABASE_URL and SUPABASE_KEY):
        return False
    body = json.dumps({
        "user_id": user_id, "kind": kind, "title": title or None, "source": source,
        "extracted": extracted, "raw_text": raw_text, "valid_from": vf, "valid_to": vt,
    }).encode()
    req = urllib.request.Request(
        f"{SUPABASE_URL}/rest/v1/user_schedules", data=body, method="POST",
        headers={"apikey": SUPABASE_KEY, "Authorization": f"Bearer {SUPABASE_KEY}",
                 "Content-Type": "application/json", "Prefer": "return=minimal"})
    with urllib.request.urlopen(req, timeout=10) as r:
        return r.status < 300


@app.post("/extract")
async def extract(file: UploadFile = File(...), kind: str = Form("fitness"),
                  user_id: str = Form("ishwar"), source: str = Form("upload"),
                  title: str = Form("")):
    """Screenshot / screen-recording / PDF → Gemini vision → structured, time-bounded
    schedule stored per user (user_schedules)."""
    if _GEMINI is None:
        return {"ok": False, "error": "extraction not configured (no GEMINI_API_KEY)"}
    data = await file.read()
    if not data:
        return {"ok": False, "error": "empty file"}
    mime = file.content_type or "image/jpeg"
    try:
        text = await asyncio.to_thread(_gemini_extract, data, mime, _extract_prompt(kind))
    except Exception as e:
        return {"ok": False, "error": f"gemini: {str(e)[:200]}"}
    try:
        parsed = _loose_json(text)
    except Exception:
        parsed = {"title": title or None, "valid_from": None, "valid_to": None,
                  "items": [], "unparsed": True}
    p = parsed if isinstance(parsed, dict) else {}
    vf, vt = p.get("valid_from"), p.get("valid_to")
    title_final = title or p.get("title") or ""
    try:
        stored = await asyncio.to_thread(_store_schedule, user_id, kind,
                                         title_final, source, parsed, text[:4000], vf, vt)
    except Exception as e:
        return {"ok": False, "error": f"store: {str(e)[:200]}", "extracted": parsed}
    return {"ok": True, "stored": stored, "extracted": parsed,
            "valid_from": vf, "valid_to": vt}


@app.get("/schedules")
def schedules(user_id: str = "ishwar", kind: str = ""):
    """Read back captured schedules for the app tab + the coach. Newest first."""
    if not (SUPABASE_URL and SUPABASE_KEY):
        return {"schedules": []}
    q = {"user_id": f"eq.{user_id}", "order": "captured_at.desc", "limit": "20"}
    if kind:
        q["kind"] = f"eq.{kind}"
    try:
        req = urllib.request.Request(
            f"{SUPABASE_URL}/rest/v1/user_schedules?{urllib.parse.urlencode(q)}",
            headers={"apikey": SUPABASE_KEY, "Authorization": f"Bearer {SUPABASE_KEY}"})
        with urllib.request.urlopen(req, timeout=10) as r:
            rows = json.loads(r.read().decode())
    except Exception:
        rows = []
    return {"schedules": rows}
