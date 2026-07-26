# Next-week plan — two parallel tracks

> Shared by laptop + mobile/cloud Claude Code. Pairs with `PRD.md`, `EXECUTION-STRATEGY.md`,
> `CURRENT-STATE.md`. Captures the plan agreed 2026-07-26/27.

## The setup
- **Ishwar this week:** reads the PRD repeatedly, decides **which users to target first** and draws
  the **MVP line** (his call — not mine), and comes back **next weekend** with a finalised
  **PRD + Roadmap (MVP + beyond) + MVP UX**.
- **Then two tracks run in parallel next week**, with Ishwar supervising from his phone. Goal:
  the **MVP in testing** with Ishwar + Uday + Jasmine.

## Track A — the fitness app (primary)
Blocked until Ishwar hands over the finalised PRD/roadmap/MVP + UX next weekend. Then:
1. Turn the finalised MVP into a `ROADMAP.md` line + a `BACKLOG.md` (verifiable tasks).
2. Build the **voice-first UX** for the MVP screens (onboarding = ONE voice screen; the coach
   interviews and files answers to Profile/Workout/History — no multi-step forms).
3. Stand up the **execution loop** (see EXECUTION-STRATEGY.md): hybrid models (Kimi/Sonnet grind
   + Claude/Fable review), token safeguards, compile/test gates, PRs, daily digest.
4. Agents run → Ishwar supervises from phone → **MVP to TestFlight** for the three.
- **Known linchpins:** the **structured-workout model** (build first — unblocks daily session,
  per-exercise HR/timing, recap, bring-your-own) and **HealthKit steps** (unlocks the Steps wedge).
- **Needs-Ishwar (queued):** vendor keys (ElevenLabs, licensed exercise-video provider,
  MusicKit/Spotify); the one video-provider choice; on-device/TestFlight; merging deploy PRs.

## Track B — the open-source "GitHub builder-agent" (byproduct; built in parallel)
The planned SECOND thing (full note: memory `github-builder-agent-idea`). A launchable repo/agent
that takes anyone **idea → PRD → tasteful UX → cost-personalized self-running agents → phone-
monitored ship.** **Built by extracting the method from Track A** (the fitness app = the reference
implementation / case study). As each fitness artifact is produced, generalise it into a reusable
`templates/` version — so the repo assembles itself ~80% for free.

**"What it entails" — the scoping to do next week (in parallel):**
- **Form factor / distribution (decide first):** clone-and-run template repo (Claude Code config
  baked in) vs GitHub App vs GitHub Action vs MCP server vs CLI installer.
- **The 5 stages as code:** `00-define` (guided PRD interview) · `01-design` (UX principles +
  design-prompt library → clickable prototypes, voice-editable via Wispr Flow) · `02-strategy`
  (analyze PRD+UX+budget/keys → cost-personalized model mix + reuse-what-exists map + BACKLOG +
  loop config) · `03-execute` (self-running loop: schedule→build→verify→PR) · `04-monitor` (daily
  digest + phone PR-review + budget guard + kill switch).
- **Model routing / cost-personalization:** BYO keys/budget; route across OpenRouter / open-source /
  Kimi / Claude (LiteLLM; the `ANTHROPIC_BASE_URL` trick for Kimi via its Anthropic-compatible endpoint).
- **Reuse-first map:** what to build ON (Claude Code, OpenHands, aider, SWE-agent, LiteLLM…) vs build.
- **Packaging:** one-command setup, `config.example`, README walkthrough, OSS license.
- **Instrument from day 1 (critical, see below):** usage counters + a "Hosted version — join
  waitlist" hook.

## If the repo takes off → company / YC path
- **The repo is the funnel; the company is a layer on top.** Natural business: a **managed/hosted
  version** (free to self-host + BYO-keys, or pay us to run it — we handle keys/billing/orchestration
  and meter model spend + margin) + **open-core / teams / enterprise** (SSO, collab, SLAs).
- **Traction that counts (not stars):** active users, **apps actually shipped with it**, retention,
  contributors/community, + commercial intent (**waitlist** + a couple of **paying design partners**).
- **Instrument usage + a waitlist from day 1** — that's what turns "a popular repo" into a
  *measurable, fundable* company.
- **Self-resolving test (the discipline):** build it, open-source it; **if it gets real usage, that's
  the earned YC story** ("N builders shipping apps with it + a hosted business"); **if it doesn't
  stick, no loss** — fitness continues. Let the test decide the pivot, not a hunch.
- **Optionality:** two possible YC stories (fitness OR the builder-agent) — apply with whichever has
  traction. Two shots on goal.

## Guardrails / discipline (agreed)
- **Fitness is first and stays the focus;** the builder-agent is a **byproduct/experiment, NOT a
  company pivot** — Ishwar's founder-market-fit is fitness + dad (memory `feedback-mvp-scope-is-ishwars`,
  `github-builder-agent-idea`).
- **MVP scope + user-targeting = Ishwar's call.** I don't inject there.
- Track B must not steal focus from Track A; it accretes from A's real work.
