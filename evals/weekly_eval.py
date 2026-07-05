"""Weekly evaluation of the voice coach.

Fetches the last 7 days of `coach-turn` generations from Langfuse (logged by
voice-agent/voice_agent.py), runs an LLM judge over each against the rubric
(rubric.py — derived from the coach's own brain), writes the per-dimension
scores back to Langfuse (so they show up on each trace), and prints a weekly
summary (averages + violations + worst examples).

Run locally:
    cd evals && pip install -r requirements.txt
    LANGFUSE_PUBLIC_KEY=... LANGFUSE_SECRET_KEY=... LANGFUSE_HOST=... \
    OPENAI_API_KEY=... python weekly_eval.py [--days 7] [--dry-run]

Scheduled weekly by .github/workflows/weekly-eval.yml.
"""

import argparse
import json
import os
from collections import defaultdict
from datetime import datetime, timedelta, timezone

from langfuse import Langfuse
from openai import OpenAI

from rubric import JUDGE_SYSTEM, build_judge_user, DIMENSIONS

JUDGE_MODEL = os.environ.get("EVAL_JUDGE_MODEL", "gpt-4o")


def fetch_coach_turns(lf: Langfuse, days: int):
    """All `coach-turn` generations in the window, across pages."""
    now = datetime.now(timezone.utc)
    since = now - timedelta(days=days)
    turns, page = [], 1
    while True:
        resp = lf.fetch_observations(
            name="coach-turn", type="GENERATION",
            from_start_time=since, to_start_time=now, limit=100, page=page)
        batch = resp.data or []
        turns.extend(batch)
        if len(batch) < 100:
            break
        page += 1
    return turns


def judge(client: OpenAI, user_line: str, context: dict, coach_reply: str) -> dict:
    resp = client.chat.completions.create(
        model=JUDGE_MODEL,
        messages=[
            {"role": "system", "content": JUDGE_SYSTEM},
            {"role": "user", "content": build_judge_user(user_line, context, coach_reply)},
        ],
        response_format={"type": "json_object"},
        temperature=0,
    )
    return json.loads(resp.choices[0].message.content)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--days", type=int, default=7)
    ap.add_argument("--dry-run", action="store_true", help="don't write scores back")
    args = ap.parse_args()

    lf = Langfuse()
    client = OpenAI()

    turns = fetch_coach_turns(lf, args.days)
    print(f"Fetched {len(turns)} coach turns from the last {args.days} days.\n")
    if not turns:
        print("Nothing to evaluate.")
        return

    sums = defaultdict(float)
    counts = defaultdict(int)
    all_violations = []
    worst = []  # (min_score, user_line, coach_reply, comment)

    for t in turns:
        inp = t.input if isinstance(t.input, dict) else {}
        user_line = inp.get("user", "")
        context = {k: inp.get(k) for k in ("hr_bpm", "whoop", "wake_mode")}
        coach_reply = t.output if isinstance(t.output, str) else json.dumps(t.output)
        if not coach_reply:
            continue
        try:
            verdict = judge(client, user_line, context, coach_reply)
        except Exception as e:
            print(f"  ! judge failed on {t.id}: {e}")
            continue

        scores = verdict.get("scores", {})
        turn_min = 5
        for dim, val in scores.items():
            if val == "n/a" or val is None:
                continue
            try:
                v = float(val)
            except (TypeError, ValueError):
                continue
            sums[dim] += v
            counts[dim] += 1
            turn_min = min(turn_min, v)
            if not args.dry_run:
                try:
                    lf.score(trace_id=t.trace_id, observation_id=t.id,
                             name=f"eval_{dim}", value=v,
                             comment=verdict.get("comment", ""))
                except Exception as e:
                    print(f"  ! score write failed: {e}")

        for viol in verdict.get("violations", []) or []:
            all_violations.append((viol, user_line, coach_reply))
        worst.append((turn_min, user_line, coach_reply, verdict.get("comment", "")))

    lf.flush()

    # --- Weekly summary --------------------------------------------------------
    print("=" * 60)
    print(f"WEEKLY COACH EVAL — {datetime.now(timezone.utc):%Y-%m-%d}  "
          f"({len(turns)} turns)")
    print("=" * 60)
    print("\nAverage score per dimension (1-5):")
    for dim in DIMENSIONS:
        if counts[dim]:
            print(f"  {dim:16s} {sums[dim]/counts[dim]:.2f}   (n={counts[dim]})")
        else:
            print(f"  {dim:16s}  n/a")

    print(f"\nViolations flagged: {len(all_violations)}")
    for viol, user_line, reply in all_violations[:15]:
        print(f"  ✗ {viol}\n      user: {user_line[:70]!r}\n      coach: {reply[:70]!r}")

    print("\nWorst 5 turns:")
    for score, user_line, reply, comment in sorted(worst)[:5]:
        print(f"  [{score:.0f}] user: {user_line[:60]!r}")
        print(f"       coach: {reply[:80]!r}")
        print(f"       judge: {comment}")

    print("\nScores written back to Langfuse (view on each trace)."
          if not args.dry_run else "\n(dry run — no scores written)")


if __name__ == "__main__":
    main()
