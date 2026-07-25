# 📖 WEEKEND PRE-BUILD BRIEF — read this first

> The one thing to read this weekend before (or while) building. Synthesizes the two North
> Stars, the build plan, and the AI-feasibility research + **my analysis** of what it means
> for what you actually do this weekend. Pointers to the deeper docs at the end.

---

## 1. TL;DR (60 seconds)
- **We're building:** a feel-good, immersive training companion — *plan → vet → adapt →
  accompany*, in your coach's voice, wherever you train. Moat = **dad's judgment + presence +
  your accumulated context** (NOT generation).
- **Two North Stars:** (1) make the person **feel good**; (2) make every workout an **immersive
  experience they're excited about** (SoulCycle-anywhere).
- **Near-term plan:** build the fitness coach (primary) + do **PN1** on the side + **dogfood on
  you + wife**.
- **Feasibility verdict:** the immersive experience is **~90% buildable RIGHT NOW** by
  assembling ~7 named tools. Your positive framing was correct — it's real, not a fantasy.
- **The discipline:** high feasibility ≠ build it all this weekend. **This weekend = reliability
  + UX shell + the demo pipeline.** The immersive "vibe engine" is a *validated next*, not a
  weekend task. Don't build the shiny layer on a broken core.

---

## 2. WHAT TO BUILD THIS WEEKEND (Part F)
1. **UX shell restructure:** multimodal **Home** (speak / type / photo) + **Workout** tab +
   **searchable History/Chat** tab + everything else in a **Profile slide-out**. (Nutrition/Whoop
   fold into the slider.)
2. **Fix the experience-breaker bugs:** #2 reopen-silence · #29 warm-up race · #34 slow start ·
   #36 Whoop race · #28 UI distortion · #39 plan-not-showing · **run #16 (`013` migration) in
   Supabase** (unblocks logging + plan/session saves).
3. **Intelligence work:** the **plan/vet/adapt** flows against arc + feel; build the
   **vet-a-workout tool** (doesn't exist yet); richer personalization; history-as-memory.
4. **F.8b — main priority: AI exercise-demo pipeline** (segment reference video → motion-transfer
   generate → **dad + sports-science verify** → tag → store → feeds mix-and-match).
5. **Decide:** what are photos *for* (form check / equipment / plan-to-vet). Give it a job.

**Kickoff order:** read this brief → gap-analysis (Part C) vs code → decide photo job →
prototype UX as an artifact → triage + fix experience-breaker bugs (run #16) → start F.8b
(segment step first). Immersive layer comes *after* the core works.

---

## 3. MY ANALYSIS — what the feasibility research means for you
**Bottom line: the immersive experience is real, buildable now, and a legitimate
differentiator — you were right to be optimistic.** But the *value* of the research isn't a
weekend task list; it's **confidence + a known stack + a sequencing map.** Here's my read:

**(a) It de-risks the vision.** The vibe-engine (A.8e) is not a moonshot — it's an *assembly*
of named tools, most production-ready. So the second North Star (immersive experience) rests on
tech that exists. You can promise it to yourself and investors honestly.

**(b) You already own ~half the foundation.** The research's recommended audio stack maps onto
what you've built: **OpenAI Realtime** (coach voice — you use it), **BackgroundAudioPlayer**
(plays audio into live runs — the mixing hook), **HR + GPS streaming** (the sensor inputs). The
immersive layer is *extending* your architecture, not starting over.

**(c) Sequencing discipline (the important part).** "It's all buildable!" is exactly the kind of
excitement that could pull you into building the shiny immersive layer before the boring core
works. **Don't.** The core loop (plan/vet/adapt/accompany) + reliability + the demo library must
be solid and *loved* first. The immersive vibe-engine is what you add to a *working, loved* core
to make it magical — not a substitute for it. Weekend = core + reliability. Vibe-engine = next.

**(d) Measure, don't assume — 3 things the research explicitly REFUTED.** Prototype and measure
these early, because unit economics decide viability (and your voice product is expensive today,
falling on the cost curve):
  - **Per-session cost** ("$0.03/min" claim refuted) — unknown; measure it.
  - **Real end-to-end latency** ("sub-500ms global" refuted) — headline TTS numbers are GPU-only;
    real cloud is ~175–200ms. Measure yours.
  - **Exercise form fidelity** of motion-transfer video (joint-level claim refuted) — unproven
    beyond short clips → **your dad + sports-science verification gate (F.8b) is the answer.**

**(e) Two things it validated that you already believed.** Motion-*transfer* (not generation) is
the right way to make correct-form demos — the form is *copied* from a real trainer clip. And
the human verification gate is exactly right for the fidelity gap. You called both.

**(f) The v1 vs v2 line (so you don't over-reach).**
  - **v1 (assemble now):** streaming coach voice (Cartesia/ElevenLabs/OpenAI Realtime) + looped
    generative ambience (ElevenLabs SFX API) + on-device spatial (Steam Audio, Apache-2.0) +
    **stem-based** adaptive music (Weav/BeatHealth pattern, cadence→BPM) + short motion-transfer
    demos (Wan-Move open / Kling closed, verified) + Gemini 2.5 Pro segmentation.
  - **v2 (near-future):** fully *generative* real-time music + longer high-fidelity form-correct
    video. Don't block v1 on these — the stem/short-clip workarounds are the v1 path.

**My one-line takeaway:** *the dream is buildable — so build the boring core first, and let the
proven immersive stack be the thing you layer on to a product people already love.*

---

## 4. WEEKEND READING LIST (the deeper docs, all on this branch)
- **`2026-07-20-product-definition-v1.md`** — the master bible: North Stars, the product
  (plan/vet/adapt/accompany), moat, user, metrics, PN1/dogfood plan, weekend plan (Part F),
  the feature set (before/after videos A.8b, vibe engine A.8e, buddy A.8c), parked nutrition
  (+ Noom), candidate instances (CAT/chemistry A.8d). **Read Parts A.0 + F first.**
- **`2026-07-20-immersive-experience-ai-feasibility.md`** — the full component-by-component
  feasibility map with named tools, latency numbers, sources, and the v1 stack. **The
  companion to Section 3 above.**
- **`2026-07-20-youth-athlete-pivot-research.md`** — the (parked) youth-athlete pivot notes.
- The published cricket-vs-tennis market artifact — context, parked.

## 5. What NOT to do this weekend (guardrails)
- Don't build the immersive vibe-engine yet (it's validated for *next*).
- Don't touch nutrition (parked; PN1 is side-learning only).
- Don't chase CAT / education / any other credential-idea (captured, parked).
- Don't over-scope the UX restructure — get the 3-surfaces + slider shell working, iterate.

---
*Weekend pre-build brief, 2026-07-20. Read alongside the master product doc and the feasibility
report. Build the core; the dream layers on top.*
