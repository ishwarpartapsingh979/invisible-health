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

**The realistic team flow it must model (this is the core insight — not a naive waterfall):**
How real product teams actually ship — **parallel with staggered locks, not sequential:**
1. **All three start together, in parallel:** PRD (product), UXD (design), and **Eng design
   thinking** (architecture / tech-design / feasibility) work **concurrently from day 1**,
   informing each other — eng flags what's cheap vs expensive, design shapes the PRD, PRD
   frames both.
2. **PRD locks first (~almost-final).** Once the PRD is *almost* finalised, it stops moving.
3. **Then UXD finalises** against the near-final PRD, **and Eng design starts finalising** in
   parallel (architecture, data model, integrations, task breakdown) — these two overlap.
4. **Only once all three are locked (PRD + UXD + Eng design) do the engineering agents start
   execution.** Execution never starts on a moving spec.
   The builder-agent must **orchestrate these three parallel workstreams with the staggered
   lock-gates**, not run a rigid 1→2→3→4 pipeline. The "define/design/strategy" stages below run
   *concurrently* and gate on locks; a `LOCKS.md`/status file tracks which of the three are frozen,
   and `03-execute` refuses to start until all three are locked.

**"What it entails" — the scoping to do next week (in parallel):**
- **Form factor / distribution (decide first):** clone-and-run template repo (Claude Code config
  baked in) vs GitHub App vs GitHub Action vs MCP server vs CLI installer.
- **The stages as code (three run concurrently, gated by locks):** `00-define` (guided PRD
  interview → **PRD lock**) ‖ `01-design` (UX principles + design-prompt library → clickable
  prototypes, voice-editable via Wispr Flow → **UXD lock**, starts finalising once PRD near-final) ‖
  `02-eng-design` (architecture / data model / integrations / feasibility + cost-personalized
  model mix + reuse-what-exists map + BACKLOG + loop config → **Eng lock**, finalises alongside UXD).
  Then — **only after all three locks** — `03-execute` (self-running loop: schedule→build→verify→PR)
  and `04-monitor` (daily digest + phone PR-review + budget guard + kill switch).
  A lightweight **`LOCKS`/status tracker** is the gate the whole thing hinges on.
- **Model routing / cost-personalization:** BYO keys/budget; route across OpenRouter / open-source /
  Kimi / Claude (LiteLLM; the `ANTHROPIC_BASE_URL` trick for Kimi via its Anthropic-compatible endpoint).
- **Reuse-first map:** what to build ON (Claude Code, OpenHands, aider, SWE-agent, LiteLLM…) vs build.
- **Packaging:** one-command setup, `config.example`, README walkthrough, OSS license.
- **Instrument from day 1 (critical, see below):** usage counters + a "Hosted version — join
  waitlist" hook.

**Open question for next-week review — model REAL multi-role, multi-round ideation (Ishwar, 2026-07-26):**
PRD + UX + Eng-design don't converge in one pass — real teams iterate through several rounds of cross-role
debate (Product proposes → Eng flags cost/feasibility → UX reshapes for delight/friction → Product revises…).
The builder-agent should model this *ideation loop*, not a single define→design→build pass — AND capturing the
debate is itself Track B's "journey" asset (the versioned reasoning trail is the shareable story, and it's what
makes the output good). **Process transparency is the product.** Ideas to evaluate:
- **Specs-as-code, versioned in PRs:** `PRD.md`/`UX-SPEC.md`/`ENG-DESIGN.md` in the repo; each round = a PR
  editing them; the **PR review thread IS the cross-role debate** — evolution (who pushed back, why) preserved.
- **Role-agents as reviewers:** a Product agent opens the spec PR; **Eng + UX agents auto-requested as
  reviewers** critique from their lens; Product revises. Rounds of review = rounds of ideation, all threaded.
- **Round-based convergence loop:** each round every role-agent critiques via its lens (Product=desirability,
  UX=usability, Eng=feasibility/cost); a synthesizer merges; repeat until **no new substantive objection OR a
  round cap** → that's the lock (feeds the LOCKS gate above).
- **RFC/ADR trail:** open Qs as Issues/Discussions (`proposed→in-debate→converging→locked`); decisions +
  **rejected alternatives + why** in `DECISIONS.md`/ADRs — nothing lost.
- **Prototype-in-the-loop for UX:** each UX round outputs an updated **clickable prototype** (versioned HTML via
  Pages) — "multiple UX ideations" = prototypes you can click through.
- **Human tiebreaker checkpoints:** after agents converge, **Ishwar reviews from phone** → lock, or send back
  with a comment (= next round's input). MVP scope/taste stays his call.
- **Traceability + ripple:** PRD feature ↔ UX section ↔ Eng section ↔ BACKLOG task linked; changing one
  **auto-flags the others for re-review** (models how a change ripples across roles).
- **Ship as `templates/`:** role-agent prompts + round-orchestration config + spec/RFC/ADR templates + the
  LOCKS state machine + review-bot Actions — so any user's idea runs the same ideation loop.

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
