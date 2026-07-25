# CURRENT STATE — read this FIRST (2026-07-25)

> This is the single orientation doc for any Claude Code session (esp. **cloud/mobile
> sessions** with no access to the local machine's memory). It consolidates the product
> direction, the locked UX, the prioritised plan, and how to work. The deeper detail is in
> the other `docs/strategy/*` files; **this file supersedes older framing where they differ.**
> **Keep this file updated at the end of every session** so the next session is oriented
> (it's our shared, in-repo memory — replaces the local machine memory cloud sessions can't see).

---

## ⏭️ LAST SESSION HANDOFF (2026-07-25, cloud) — READ THIS TO REVIEW & TAKE OVER
**Branch:** `claude/travel-base-branch-visibility-xayckv` (based on `travel-base`). **Nothing merged, no PR, nothing deployed.** 3 new commits on top of `travel-base`:

| Commit | What | Risk |
|---|---|---|
| `58ae23e` | **Multi-user backend** — agent derives `user_id` from participant identity (`_user_id_from_identity` strips `-ios`/`-watch`/`-web`; `wait_for_participant`, 10s timeout, `"ishwar"` fallback). `SessionStore` gets an instance `user_id`; method params default to it (call sites unchanged). All inline `"ishwar"` writes + tracer + rule-firing log use the derived id. | Low — back-compat `ishwar-ios → ishwar` verified; but it IS live agent behavior, dogfood right after merge. |
| `88a66ad` | **VET-a-workout tool** — `vet_workout` function-tool + `RulesEngine.vet_prompt` → ENDORSE/MODIFY/SWAP verdict on a plan the user brings, off the same rules. Surfaced in the coach prompt. | Low — net-new tool, no existing behavior touched. |
| `c131e51` | Docs (this file §8). | None. |

**Verified in-cloud:** `py_compile` both files ✅; identity logic 7/7 cases ✅; `vet_prompt` all 4 verdict shapes ✅. **Not run:** real agent / LiveKit / OpenAI / Supabase (no prod touch).

**HOW TO REVIEW (laptop Claude Code):** ask it to `git fetch && git log --oneline origin/main..claude/travel-base-branch-visibility-xayckv` then `git diff origin/main...claude/travel-base-branch-visibility-xayckv` — or open a PR for the GitHub diff view.

**✅ YOUR PARTS (start here):**
1. **Review + merge** the branch → CI auto-deploys the agent → dogfood: say *"my trainer wants 5x5 heavy squats today, should I?"* (should trigger VET) and confirm a normal session still saves under you.
2. **Run migration** `infra/migrations/013_local_dates.sql` in Supabase (still pending, unrelated to above; phone-doable).
3. **iOS (Xcode) — the multi-user client half** (not started; needs a design call, see §8):
   - `Invisible_Health/Voice/VoiceConfig.swift:29` — `participantIdentity = "ishwar-ios"` → per-user.
   - `PlanTabView.swift:138`, `NutritionTabView.swift:150`, `ShowMeSheet.swift:93,441` — hardcoded `user_id=ishwar` → per-user.
   - Pairs with **Sign in with Apple**. (Cloud can pre-write this Swift on request — just can't build it.)

---

## 1. What we're building (canonical)
A **workout EXPERIENCE app, backed by career professionals & pro-athlete coaches.**
Tagline: **"Hyper-personalised fitness experiences, designed by pro-athlete coaches with 40+
years of experience."**

- **Two North Stars:** (1) make the person **FEEL GOOD** (warm, anti-guilt, presence-not-
  surveillance, celebrate effort); (2) every workout is an **IMMERSIVE EXPERIENCE you crave**
  (SoulCycle/Peloton-anywhere — personalised, adaptive). **The immersive experience is THE
  crux**, not a phase-2 add-on.
- **Two-layer model:** the **EXPERIENCE** (immersive delivery) = the product; the **WORKOUT**
  (the payload) is either **ours** (coach-designed) **or yours** (bring your own plan/goal →
  we VET + wrap it). Bring-your-own is the low-friction on-ramp.
- **Four functions:** **PLAN** (right workout from your arc, via the rules engine) · **ADAPT**
  (reshape to how you feel; what you SAY overrides the wearable) · **VET** (check a plan you
  bring — the "why not ChatGPT" answer; *this tool does NOT exist yet, build it*) · **ACCOMPANY**
  (the always-on coach with you through the session).
- **Moat:** the **experience × the pro-coach backing** (dad = 40 yrs + Ranji + sports-science +
  nutritionist colleagues) — real, credentialed, uncopyable. **NOT generation** (a commodity).
- **Founder-market fit:** Ishwar lives the need (dad coaches him remotely from Chandigarh),
  built it, and MISSED it after 2 weeks away.
- **Nutrition is PARKED** (the big second act — reframed as an *adherence* problem; revive later
  WITH a real nutritionist). **Fitness companion is the wedge, built first.** Any nutrition-
  concierge / maid / wallet / Zepto material from older notes is parked.
- Dogfood cohort: **Ishwar + brother Uday + wife Jasmine** (Jasmine is a group-class person =
  the "wrong user" for a gym companion → dogfood for *learning/product-love, not validation*;
  still need ~5 external motivated solo trainers for real validation).

## 2. The LOCKED voice-first UX (see `ux-prototype.html` at repo root)
Design direction is agreed. **Voice is THE interface; buttons are the exception.**
- **Home = a centered voice canvas** (listening halo + "tap to talk" + a glanceable you↔coach
  exchange). A **small Experiences pill** at the bottom → opens a browser: see all experiences +
  **"create your own"** (describe any vibe by voice) + tap to **apply**, then Begin.
- **Tabs (bottom): Home · Workout · History · Profile** — tabs/profile are NOT voice-first;
  direct-tap lookup. **History = a transcript of what you SAID + what the AI replied** (you→coach
  pairs, grouped by day, searchable). Workout/Profile are fine for now, refine later.
- **Always-on coach** (the USP): a persistent minimal coach presence; **one tap to turn off any
  second** ("stop listening"). Multimodal (speak / type / photo), speak primary.
- **Once a workout STARTS the phone is pocketed** — everything is **AirPods audio** (coach voice
  + world soundscape + music); **tracking is on the Watch / Whoop**. So the in-session screen is a
  calm **"rest" state** (no stats dashboard, no on-screen world-picker, no post-workout screen).
- **The experience is controllable DURING the workout by VOICE** — "change the vibe / make it a
  beach run" swaps it live (worlds, music, intensity), no screen.

## 3. The prioritised plan (build order)
**Execution philosophy: plumbing first → ship to real people → collect data → improve.**
"Plumbing" (build FIRST) = reliable core loop + experience framework + personalisation inputs +
**MULTI-USER** + **DATA CAPTURE**. v1 experiences can be simple but instrumented.

- **P0 — Foundation (get Uday & Jasmine using it):**
  1. **Multi-user** — un-hardcode `user_id="ishwar"` (the one real blocker; see §4).
  2. Sign in with Apple (iOS) → identity flows to token → agent → Supabase.
  3. **Run migration `#16` `013_local_dates.sql`** in Supabase (silently blocks plan/session/log
     saves).
  4. Reliability: #2 reopen-silence, #29 warm-up race, #34 slow start, #36 Whoop race, #39
     plan-not-showing, #28 UI.
  5. Workout-only scoping (hide nutrition/eating surfaces); wearable-optional (Whoop = Ishwar
     only; others run on RPE/subjective + Apple Health).
  6. **Data capture / instrumentation** (Langfuse per-user + log experience/feel/completion).
  7. TestFlight to Uday + Jasmine.
- **P1 — Make it good:** the **VET-a-workout tool** (missing) · first-class **ADAPT-now** ·
  **coach craft** in the voice (arc → climb → peak → finish, mantras, countdowns, "you're seen")
  · pro-coach-backing framing · the **steps/daily-goal coach** (HealthKit + a gap-closing walk).
- **P2 — Immersive engine:** one ambience "world" → world library → adaptive audio (cadence→BPM
  stems) → spatial "pack" (Steam Audio) → before/after videos → the **workout-video pipeline**
  (Gemini segment → motion-transfer generate → **dad+sports-sci verify gate** → tag → store).
- **P3 — Scale:** external validation, measure real cost+latency, supply-side (more coaches),
  nutrition act-2.

## 4. Technical map (how a request flows) + the multi-user blocker
- **`voice-agent/voice_agent.py`** — hosted agent (LiveKit Cloud Agents + OpenAI Realtime
  `gpt-realtime-2.1`). One `CoachAgent` + function-tools. Delivers decisions from the rules engine.
- **`voice-agent/rules_engine.py`** — coaching decisions are DATA in Supabase `rules` (dad ×
  sports-science × nutritionist). To change behaviour, change the rules (a migration), not prose.
- **Supabase** (project `pnbrjxgmaulijamhcyik`) — tables `rules, user_profiles, planned_workouts,
  nutrition_log, user_facts, conversations, coaching_sessions`. **All keyed by `user_id`.**
- **`voice-token-server/main.py`** — FastAPI on Cloud Run; mints LiveKit tokens (`/token` takes
  an `identity`) + serves `/workout` `/nutrition` (+ `/extract` `/schedules` from the parked
  Show-Me). iOS has NO Supabase SDK — data tabs read these endpoints.
- **iOS** (`Invisible_Health/`, SwiftUI) — talks to the agent over the LiveKit data channel
  (`VoiceCallManager`); reads data tabs over HTTP.
- **THE MULTI-USER BLOCKER:** `user_id="ishwar"` is hardcoded — agent (`voice_agent.py:~2468` +
  `SessionStore` method defaults + a few inline writes), iOS (`/workout?user_id=ishwar` etc.).
  The token already carries an `identity`; the fix = agent derives `user_id` from the joining
  participant's identity, iOS sets a per-user identity, stop defaulting to "ishwar". Small,
  mostly plumbing. **Keep a back-compat "ishwar" fallback so nothing breaks before iOS ships.**

## 5. Deploy & verify (IMPORTANT for cloud/mobile)
- **CI auto-deploys on push to `main`** (`.github/workflows/deploy.yml`): token server + backend +
  the **voice agent** (`deploy_agent` job). So: make the fix → PR → merge → it ships. A cloud
  session should NOT run `lk agent deploy` (pushing is the deploy).
- **The agent runs server-side** → the **already-installed iOS app immediately uses new agent
  behaviour after a deploy.** So agent/backend changes are **dogfoodable from the phone, laptop
  closed** — merge → talk to the app.
- **Migrations are NOT automatic** — add the `.sql` in `infra/migrations/` and FLAG it; Ishwar
  runs it in the Supabase SQL editor (doable from the Supabase web dashboard on a phone).
- **iOS cannot be built in the cloud** (no Xcode) → batch Swift work for when the laptop is open;
  do all backend/agent work from mobile. After Python edits, `python -m py_compile` the file.

## 6. How to work with Ishwar (preferences)
- **Be eager and action-first.** Don't front-load warnings/risk-tables/"can't be done." If there's
  a real constraint, one line + the workaround, then keep moving.
- **Get approval before code changes** by default, but move fast once given.
- Voice-first, minimal-UI thinking for anything user-facing.
- Match the surrounding code's style; `py_compile` Python; never commit secrets or large binaries.

## 7. Mobile workflow (laptop mostly closed)
1. On the phone: claude.ai/code or the Claude app → the connected `invisible-health` repo →
   start a session **on branch `travel-base`** (this branch has all context + the prototype).
2. Give it a task (backend/agent/migration/docs). It works in the cloud → opens a PR.
3. Review + merge from the phone → CI deploys → talk to the app to dogfood.
4. **End every session by updating THIS file** (§8) so the next session is oriented.

## 8. What to build next (living list — update me)
- [x] **Multi-user backend** — DONE (branch `claude/travel-base-branch-visibility-xayckv`,
      2026-07-25). Agent derives `user_id` from the joining participant's identity
      (`_user_id_from_identity` strips a `-ios`/`-watch`/`-web` client suffix → stable id;
      `wait_for_participant`, 10s timeout, `"ishwar"` fallback). `SessionStore` holds an
      instance `user_id`; per-method params default to it so call sites are unchanged. All
      inline `"ishwar"` writes + tracer + rule-firing log now use the derived id. Back-compat:
      today's `"ishwar-ios"` → `"ishwar"`, so nothing changes for the current user.
      **Still needs (LAPTOP/iOS):** app sends a real per-user identity (`participantIdentity`
      + `/workout?user_id=` etc. are still hardcoded `ishwar`) — pairs with Sign in with Apple.
- [x] **VET-a-workout tool** — DONE (same branch/date). `vet_workout` function-tool: checks a
      workout the user BRINGS against the same rules + their state → ENDORSE/MODIFY/SWAP verdict
      (`RulesEngine.vet_prompt`). Surfaced in the coach prompt. *Next: real dogfood + maybe a
      "log the vetted plan" follow-through.*
- [ ] **Reliability:** #29 warm-up race + #2 reopen-silence; add migration `#16` and flag it.
- [ ] **Coach craft** in the agent prompt (arc/mantra/peak/countdown/"you're seen").
- [ ] iOS (LAPTOP): Sign in with Apple + send per-user identity + workout-only scoping.
- Parked: Show-Me screen-recording (code exists, off-surface), nutrition concierge/wallet, the
  broadcast extension `ShowMeBroadcast`.

---
*Deeper docs on this branch: `2026-07-20-product-definition-v1.md` (master bible),
`-WEEKEND-PRE-BUILD-BRIEF.md`, `-immersive-experience-ai-feasibility.md`. UX: `/ux-prototype.html`.*
