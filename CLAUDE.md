# Invisible Health — project guide for Claude Code

This file orients any Claude Code session (including cloud/mobile sessions started
from claude.ai/code) that does NOT have the local machine's memory. Read it first.

## What this is
An iOS app + a hosted, voice-first **all-day health guide** (not just a gym coach).
The user (Ishwar) talks to it any time for **training, nutrition, recovery, and
motivation**. The brain fuses three sources: his **dad's coaching rules**, **sports
science** (RPE / load management), and his **nutritionist's rules**. Core principle:
**what the user SAYS overrides the wearable number** (subjective + safety win).

## Product strategy & positioning (as of 2026-07 — Ishwar's direction)
The thesis sharpened during dogfooding. **Keep this front of mind when prioritising.**
- **Core hypothesis (the "why" above everything):** jobs are hectic and only getting
  more so, so the winning product makes staying healthy **effortless** for time-poor
  people. Make it as easy as possible to (a) eat good, healthy food, (b) get in touch
  with **specialists** (nutritionist, trainer), and (c) do **cardio / strength**. It all
  goes hand in hand — minimise their planning/time cost and keep **help always on hand**.
  Lower the friction → they do more of it → they stay healthy. **Every feature should be
  judged by: does this make health *easier* for a busy person?**
- **Original hypothesis (now narrowed):** "people want someone to talk to in the gym."
  Problem: the gym is ~1 hour/day; only already-**motivated** people go (and motivating
  the unmotivated online is a hard, unsolved problem); of the motivated, many prefer
  group classes or want a companion (like Jasmine) but **not** a coach talking at them
  the whole time. Each cut shrinks the market. So a gym-companion product is a small TAM.
- **The pivot — nutrition-first, 80/20:** **Nutrition is ~80% of the value, workouts ~20%.**
  Build BOTH (fat loss *and* muscle + cardio health — never cardio-only), but lead with
  nutrition. The **dad + his colleagues (nutritionist)** own the **connection** between
  the two. This fits the Indian market: people don't work out much but care a lot about
  **food** — so a food-first product has a bigger, more reachable market.
- **The product = a nutrition concierge (end-to-end), plus the 20% training.** For people
  who don't have time to manage it themselves: plan the week **and** the day around their
  conditions; adapt when they dislike the plan or go off-script (re-plan, don't punish);
  check what's available vs. not; plan groceries and get them **delivered via quick-commerce**;
  run a **weekly nutrition review** and liaise with the nutritionist; and layer the 20%
  workout (muscle + cardio) on top. Everyone will do *something* for their health — funnel
  the easy 80% (food) first, then the 20% (training).
- **Implication for the backlog:** weight nutrition depth, personalisation, and the
  concierge/automation issues above pure workout features. (See issues #35, #41, #42, #43,
  #44, #45 and the concierge issue.)
- **Voice-first is the enduring interface (keep this architecture).** The **home is always
  voice** — the user keeps asking by voice and always gets the answer, details, and chat
  history there. **Text is secondary:** when they want to read text/chat or see detailed
  data, they go to the **other tabs** (Workout, Nutrition, Profile, Whoop). Voice stays the
  front door; text/data tabs support it — we do NOT replace voice with a text-first UI.
  (Text-as-secondary is tracked in #40.)

## Architecture (how a request flows)
- **`voice-agent/voice_agent.py`** — the hosted agent (LiveKit Cloud Agents +
  OpenAI Realtime, `gpt-realtime-2.1`). One `CoachAgent` with function-tools. This
  is the brain; it DELIVERS decisions, it does not invent them.
- **`voice-agent/rules_engine.py`** — the **rules engine**. Coaching decisions are
  DATA in the Supabase `rules` table (trigger_conditions → action_forces /
  action_vetoes + rationale + tier + source + domain), matched + resolved
  deterministically here. Vetoes are absolute; tiers 0 safety > 1 arc > 2 sizing >
  3 preference; dad > sports_science on ties. The LLM must follow what
  `get_active_coaching_rules` returns. **To change coaching behavior, change the
  rules (a migration), not prose in the prompt.**
- **Supabase** (Postgres, project `pnbrjxgmaulijamhcyik`) — source of truth. Tables:
  `rules`, `rule_firings`, `coaching_sessions`, `user_profiles`, `planned_workouts`,
  `nutrition_log`, `user_facts` (personalization flywheel), `conversations`. The
  agent reads/writes via REST (aiohttp) using `SUPABASE_URL` + `SUPABASE_SERVICE_KEY`.
- **`voice-token-server/main.py`** — small FastAPI on Cloud Run. Mints LiveKit join
  tokens (`/token`) AND serves the app's read-only data: `/nutrition` and `/workout`
  (reads Supabase server-side). **The iOS app has NO Supabase SDK** — data tabs read
  through these endpoints so they work without a live voice session.
- **iOS app** (`Invisible_Health/`, SwiftUI) — tabs: Voice (home, tab 17), Workout
  (19), Nutrition (20), Profile (18), Whoop (15). Talks to the agent over the
  **LiveKit data channel** (`VoiceCallManager`) and reads data tabs over HTTP from
  the token server. Wearable data comes from a separate **Open Wearables** backend.
- **`evals/`** — weekly LLM-judge eval (`weekly_eval.py` + `rubric.py`, 12
  dimensions) over Langfuse traces. `infra/queries/weekly_activity.sql` = objective
  counts. Scheduled by `.github/workflows/weekly-eval.yml`.

## Deploy & verify — IMPORTANT for cloud/mobile sessions
- **Everything deploys via GitHub Actions on push to `main`** (`.github/workflows/
  deploy.yml`): the token server + backend + the **voice agent** (the `deploy_agent`
  job uses `livekit/deploy-action`; LiveKit + runtime secrets are GitHub secrets).
  So: **make the fix, open a PR, merge → it ships.** A cloud session should NOT try
  to run `lk agent deploy` (no LiveKit CLI/auth in the cloud) — pushing is the deploy.
- **Database migrations are NOT automatic.** New SQL in `infra/migrations/` must be
  run by Ishwar in the Supabase SQL editor. If a fix needs a new migration, ADD the
  `.sql` file and **clearly flag in the PR that it must be run** — don't assume it's
  applied. Migrations are written to be idempotent (create-if-not-exists;
  delete-then-reinsert for reseeds).
- **iOS cannot be built/run in a cloud session.** Do the Swift change + a careful
  read; Ishwar rebuilds in Xcode and verifies on device. New `.swift` files under
  the synchronized groups auto-include (no pbxproj edit needed).
- After Python edits, `python -m py_compile` the changed file as a sanity check.

## Conventions / gotchas
- Match the surrounding code's style, comment density, and idioms.
- **Never commit** secrets, `**/venv/`, `*.wav`, `*.pt`, `wakeword-training/`, or
  large binaries (see `.gitignore` — a past `git add -A` swept in ~51k audio clips
  and blew up the push).
- Two Swift Codable models were renamed to avoid Apple collisions: our plan struct
  is **`CoachPlan`** (not `WorkoutPlan`), exercise card is **`ExerciseDemoCard`**.
- The rules matcher (`rules_engine.py`) treats `/` and `,` in a trigger as OR and
  supports numeric comparison triggers (`">=2"`); keep its self-test passing.
- Adding a data-tab field = add it to the token-server endpoint AND the iOS Codable
  model (tolerant `decodeIfPresent`).

## How to work a bug (typical loop)
1. Reproduce from the description; locate the layer (agent / rules / token server /
   iOS / migration).
2. Make the minimal fix in that layer.
3. `py_compile` any Python; sanity-check Swift by reading.
4. If it needs SQL, add the migration and flag it.
5. Open a PR with a clear summary + any manual steps (migrations, Xcode rebuild).
