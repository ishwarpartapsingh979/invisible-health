# Execution Strategy — autonomous week + models + token safeguards

> How we execute the PRD (`PRD.md`) with agents over a week while Ishwar does his day job.
> Shared by laptop + mobile/cloud Claude Code sessions. Pairs with `CURRENT-STATE.md`.

## The model strategy (cost-aware, hybrid)
Autonomous week-long execution is token-heavy, so **split the work by model**:
- **The grind → a cheap, strong agentic-coding model (Kimi K2).** Routine implementation,
  migrations, scaffolding, repetitive tasks. Kimi ships an **Anthropic-compatible endpoint**, so
  Claude Code can drive it via `ANTHROPIC_BASE_URL` + a Kimi key — **same harness, cheap tokens.**
  Big win: it **does NOT burn the Claude weekly cap**, so Claude/Fable stays free for review + the
  day job.
- **Design + review → frontier Claude (Sonnet/Opus) or Fable 5.** The architecture calls (the
  structured-workout model, the Vibe-engine shape) and the **review pass** on the grind's PRs
  before they merge. Frontier still leads on hard, long-horizon reliability — which is exactly
  where unsupervised runs are riskiest.
- **Simplest fallback (no proxy setup):** stay in Claude Code, run the grind on **Sonnet** (much
  cheaper than Opus), Opus/Fable for review. Add Kimi later to cut cost further.
- **Non-negotiable with a cheaper grinder:** hard compile/`xcodebuild`/test gates + small PRs +
  daily review. The gates catch the cheaper model's mistakes.
- Note: this is the model that **builds** the app. The app's **runtime coach** is still
  OpenAI Realtime + Gemini — unchanged regardless.

## Token tracking + safeguards
**Track:** `/usage` (plan limits + remaining — check first), `/cost` (session), `ccusage`
(`npx ccusage@latest` — daily/weekly per-model token+cost), Console (API spend + hard limits/alerts).

**The plan's multiple limits:** subscription has a **5-hour rolling** limit + a **weekly** limit
(the binding one) + a **tighter weekly cap on Opus** than Sonnet. API = metered $ (wallet is the limit).

**Safeguards + thresholds (and why):**
| Safeguard | Threshold | Why |
|---|---|---|
| Model-tiering | Kimi/Sonnet for the grind; Opus/Fable only for review/design | Biggest lever; Opus weekly cap is tightest — don't burn it autonomously |
| Cadence cap | 4–6 scheduled runs/day, one bounded task each (not a continuous loop) | Predictable spend, coherent output |
| Weekly budget + pause | Pause the loop at ~70% of the weekly limit (or a $ ceiling on API) | Leave headroom for review + your own use; avoid mid-week throttle |
| Per-run cap | Abort a run over ~X tokens | Runaway guard |
| Daily monitor | Check `/usage`/ccusage each evening | Catch drift early |
| Fresh session per task | New context per task | Context accumulation is a hidden cost multiplier |
| Kill switch | One command to pause | Safety |

**By tier (confirm via `/usage`):** Max 20× → viable with grind-on-cheap-model + pause at 70%;
Max 5× → tighter, babysit; Pro → targeted manual runs, not a loop; API → set a weekly $ ceiling +
alert in Console.

## The autonomous loop (how the week runs)
1. Source of truth: `PRD.md` + a `BACKLOG.md` (PRD decomposed into ~25 verifiable tasks, each with
   spec + acceptance + verify command, tagged `[autonomous] / [needs-device] / [needs-Ishwar]`).
2. Scheduled runs (several/day): read BACKLOG + CURRENT-STATE → pick top unblocked task →
   implement e2e → **verify (py_compile / xcodebuild sim / tests)** → open a **PR** → update
   BACKLOG + CURRENT-STATE → append to `DAILY-DIGEST`. Blocked on key/decision/device → log to
   `NEEDS-ISHWAR`, skip to next.
3. Guardrails: compile-gated; **PRs not direct-to-main** for anything that deploys the coach;
   small atomic changes; auto-merge OK for internal/non-deploy, hold deploy-affecting for Ishwar.
4. Ishwar's daily ritual (~5 min, from phone): read the digest, merge good PRs, answer NEEDS-ISHWAR.

## Build order (from PRD anchors)
1. **Structured-workout model** (the linchpin). 2. **Anon-first + `/claim`** (un-gate the app).
3. **Steps wedge backend** (goal + gap + offer + walk pacing; HealthKit steps). 4. **Coach
real-time upgrades** (per-exercise timing/HR/rest, cool-down, controls). 5. **Exercise Video
Library** (provider-agnostic + fallback). 6. Recap · Hype-film scaffold · **Vibe-engine
scaffolding** (behind flags). 7. **Admin: Reference Ingestion** (structure-only, IP-safe).

## What needs Ishwar (queued, non-blocking)
Vendor accounts + API keys (ElevenLabs, licensed video provider, MusicKit/Spotify); the one vendor
choice (which video provider); on-device / TestFlight testing; merging deploy-affecting PRs.

## Next weekend — UI overhaul (voice-first)
Current UI has too many screens. **Collapse toward voice-first:** onboarding becomes **ONE voice
screen** — the coach *interviews* you (goal, time, likes/dislikes, etc.) conversationally and
**files answers into Profile / Workout / History**, not a multi-step form. Apply the same "remove
screens, ask by voice, store to the right tab" rule everywhere. Prototype: `ux-prototype.html`
(locked core) + `ux-designs.html` (flows in progress — the stepped onboarding there is to be
replaced by the one-screen voice version).
