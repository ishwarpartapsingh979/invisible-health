# CURRENT STATE — read this FIRST (2026-07-25)

> This is the single orientation doc for any Claude Code session (esp. **cloud/mobile
> sessions** with no access to the local machine's memory). It consolidates the product
> direction, the locked UX, the prioritised plan, and how to work. The deeper detail is in
> the other `docs/strategy/*` files; **this file supersedes older framing where they differ.**
> **Keep this file updated at the end of every session** so the next session is oriented
> (it's our shared, in-repo memory — replaces the local machine memory cloud sessions can't see).

---

## ⏭️ LAST SESSION HANDOFF (2026-07-25, cloud) — READ THIS TO REVIEW & TAKE OVER
**Branch:** `claude/travel-base-branch-visibility-xayckv` (based on `travel-base`). **Nothing merged, nothing deployed.** Code/doc commits on top of `travel-base`, grouped by theme:

| Theme | Commit(s) | What | Risk |
|---|---|---|---|
| **Multi-user backend** | `58ae23e` | Agent derives `user_id` from participant identity (`_user_id_from_identity` strips `-ios`/`-watch`/`-web`; `wait_for_participant`, 10s timeout, `"ishwar"` fallback). `SessionStore` gets an instance `user_id`; method params default to it (call sites unchanged). All inline `"ishwar"` writes + tracer + rule-firing log use the derived id. | Low — back-compat `ishwar-ios → ishwar` verified; live agent behavior, dogfood after merge. |
| **Multi-user iOS** | `5f03d01` | Sign in with Apple: `AuthManager` + `SignInView` gate; `VoiceConfig.currentUserId`/`participantIdentity` per-user + `devUserIdOverride`; data tabs un-hardcoded; `applesignin` entitlement added to both `.entitlements`. | Med — **needs Xcode** (capability + build) & a continuity call, see YOUR PARTS. |
| **VET tool** | `88a66ad` | `vet_workout` function-tool + `RulesEngine.vet_prompt` → ENDORSE/MODIFY/SWAP verdict on a brought plan, off the same rules. Surfaced in the coach prompt. | Low — net-new. |
| **#29 warm-up race** | `85a9616` | Agent emits `agent_ready` when the session is truly live; iOS gates `agentReady` on that (not premature participant-join). 5s fallback kept. | Low. |
| **Coach craft** | `b08b52d` | In-workout delivery guidance (presence/arc/peak/"seen") in the STYLE prompt. | **Review the voice** — taste-dependent, but 1-commit revert. |
| **Music at onboarding** | `93d524b` | `MusicConnectionManager` + `MusicConnectView` (tappable onboarding step); Apple Music auth via MusicKit; `music_service` streamed to the coach. Spotify = preference only. | Med — **needs Xcode** (MusicKit capability + `NSAppleMusicUsageDescription`); playback engine not built. |
| **Docs** | `c131e51`, `852bb09`, … | This file. | None. |

**Verified in-cloud:** `py_compile` agent + rules_engine ✅; identity logic 7/7 ✅; `vet_prompt` all 4 shapes ✅. Swift read carefully (can't compile in cloud). **Not run:** real agent / LiveKit / OpenAI / Supabase (no prod touch).

**HOW TO REVIEW (laptop Claude Code):** `git fetch && git log --oneline origin/main..claude/travel-base-branch-visibility-xayckv` then `git diff origin/main...claude/travel-base-branch-visibility-xayckv` — or open a PR for the GitHub diff view. (Merging the branch/PR = the push to `main` that fires your `deploy.yml`; it never auto-deploys on its own.)

**✅ YOUR PARTS (start here):**
1. **Review + merge** → your `deploy.yml` ships agent+token-server. Dogfood: *"my trainer wants 5x5 heavy squats today, should I?"* (→ VET); confirm a normal session still saves under you; check the coach voice feels right (coach-craft); confirm no warm-up speech loss (#29).
2. **iOS (Xcode) — build the written client code** (build + verify on device):
   - Enable the **Sign in with Apple** capability (Signing & Capabilities) so provisioning carries the entitlement.
   - Enable the **MusicKit capability** + add an **`NSAppleMusicUsageDescription`** (build settings) so Apple Music connect works.
   - **Continuity call:** set `VoiceConfig.devUserIdOverride = "ishwar"` on your build to keep your history + skip the gate; leave `nil` for the shared TestFlight build (Uday/Jasmine sign in and get their own ids). If you sign in fresh instead, tell me your Apple `user` id and I'll write a one-time Supabase remap of your `"ishwar"` rows.
   - New `AuthManager.swift` + `MusicConnectionManager.swift` auto-include (synchronized group).
3. **Run migration** `infra/migrations/013_local_dates.sql` in Supabase (still pending, unrelated; phone-doable).

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
- [x] **Multi-user iOS (Sign in with Apple)** — DONE (same branch, code-complete; **build in
      Xcode**). `AuthManager` + `SignInView` gate; `VoiceConfig.currentUserId`/`participantIdentity`
      per-user + `devUserIdOverride` continuity hatch; data tabs un-hardcoded; `applesignin`
      entitlement added. **Your parts:** enable the Sign in with Apple capability + build; decide
      the override vs. a Supabase row-remap for your history (see handoff §top).
- [x] **VET-a-workout tool** — DONE (same branch/date). `vet_workout` function-tool: checks a
      workout the user BRINGS against the same rules + their state → ENDORSE/MODIFY/SWAP verdict
      (`RulesEngine.vet_prompt`). Surfaced in the coach prompt. *Next: real dogfood + maybe a
      "log the vetted plan" follow-through.*
- [x] **ADAPT-now flow** — DONE (2026-07-25, `main`). `adapt_session` function-tool: reshapes the
      session the user ALREADY has to how they feel right now ("tired / sore / short on time") →
      KEEP / EASE / SWAP directive (`RulesEngine.adapt_prompt`), delivered as responsiveness not
      policing. Nudged in the MOTIVATION prompt block (adapt vs vet). *Next: dogfood the phrasing.*
- [x] **Reliability #29 (warm-up race)** — DONE. Agent emits `agent_ready` when the session is
      truly live; iOS gates readiness on it (not the premature participant-join). **#2
      (reopen-silence) was already CLOSED** (unique room per open, `VoiceCallManager.swift:90`).
      *Still open: migration `#16` `013_local_dates.sql` needs running in Supabase.*
- [x] **Coach craft** — DONE (`b08b52d`). In-workout delivery block in the STYLE prompt
      (presence/arc/peak/"seen"). Taste-dependent — **listen when dogfooding**; 1-commit revert.
- [x] iOS: **workout-only scoping** — DONE (2026-07-25, `main`). NUTRITION tab hidden in
      `ContentView` (view code kept for act-2). Also added `NSAppleMusicUsageDescription` to the
      app build settings (so the MusicKit connect step doesn't trap on device). Full app
      **compiles** (simulator build green). **Left for MusicKit:** enable the MusicKit + Sign in
      with Apple capabilities in Xcode Signing & Capabilities, then build on device.
- [~] **Connect Apple Music / Spotify at onboarding** (Ishwar, 2026-07-25) — music is part of the
      immersive experience (coach voice + world soundscape + **music** over AirPods, §2).
      **DONE (cloud, `93d524b`):** `MusicConnectionManager` + `MusicConnectView` (tappable step in the
      onboarding form); captures the choice + requests Apple Music auth via **MusicKit**; `UserProfile`
      streams `music_service` and the agent surfaces it to the coach. Spotify records the preference only.
      **STILL NEEDS (you):**
      - **Xcode:** add the **MusicKit capability** + an **`NSAppleMusicUsageDescription`** (build
        settings — the app has no checked-in Info.plist), else `MusicAuthorization.request()` traps.
        New `MusicConnectionManager.swift` auto-includes.
      - **Spotify (later):** register a **Spotify Developer app** (client id + redirect URI), add the
        **Spotify iOS SDK** (SPM) + URL scheme + `LSApplicationQueriesSchemes`; connect via `SPTAppRemote`.
      - **Design call → then the engine:** control playback **in-app** (Apple Music can; the experience
        picks/adapts music) vs **hand off** to their app. I scaffolded toward in-app control; playback
        itself (choosing/adapting tracks in-session) is not built yet.
- Parked: Show-Me screen-recording (code exists, off-surface), nutrition concierge/wallet, the
  broadcast extension `ShowMeBroadcast`.

---
*Deeper docs on this branch: `2026-07-20-product-definition-v1.md` (master bible),
`-WEEKEND-PRE-BUILD-BRIEF.md`, `-immersive-experience-ai-feasibility.md`. UX: `/ux-prototype.html`.*
