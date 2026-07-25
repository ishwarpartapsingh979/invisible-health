# Immersive Experience — AI Feasibility Research (mid-2026)

> **How this was produced (token transparency):** a deep-research fan-out — **111 AI
> sub-agents**, ~**3.6M tokens**, ~41 min. Pipeline: decompose → 6 parallel web-search
> angles → fetch **28 sources** → extract **47 claims** → adversarially verify the top **25**
> (3-vote each) → **22 confirmed, 3 refuted** → synthesize. Every claim below carries its
> vote and sources. Mid-2026 snapshot; a fast-moving field.

## HEADLINE VERDICT
**The full immersive-adaptive-feel-good experience is largely buildable RIGHT NOW** by
*composing* named existing tools, layer by layer. Nothing in the core vision requires
unreleased tech. The two most rock-solid pieces are the **live coach voice** and the
**soundscape/spatial audio**. The two you *work around* (not block on) are **fully-generative
real-time music** (use stem-adaptation instead) and **long form-perfect demo video** (use
short motion-transfer clips instead). Two economic assumptions (cost/latency) were **refuted**
— measure them yourself, don't budget on them.

---

## 1. LIVE PERSONALIZED COACH VOICE — ✅ feasible now (HIGH, 3-0)
Multiple TTS vendors now deliver **sub-100ms streaming time-to-first-audio**, well inside the
~500ms conversational budget. Latency is *no longer the differentiator* — competition has
moved to emotion/prosody/cost.
- **Closed:** Cartesia **Sonic Turbo ~40ms** (market-fastest), Cartesia Sonic-3 ~90ms,
  **ElevenLabs Flash v2.5 ~75ms**, **Rime Coda sub-100ms**. Emotion leaders: **Inworld
  TTS-1.5, Hume Octave, Fish Audio S2**. **OpenAI Realtime-2** (shipped May 7 2026) collapses
  STT+TTS into one GPT-5-class speech-to-speech model (96.6% Big Bench Audio, 128K context).
- **Open-source** (from the brief; not the subject of surviving verified claims): XTTS/Coqui,
  StyleTTS2, F5-TTS, Kokoro, Piper.
- **Honest nuance:** several headline latencies are model/GPU TTFB, not full networked
  end-to-end → real-world cloud latency ~175–200ms (still real-time). **Voice-cloning quality
  + the consent/ethics/licensing path for cloning dad's voice was NOT independently verified**
  → open question.
- Sources: coval.ai TTS-2026, inworld.ai TTS benchmarks, openai.com.

## 2. ADAPTIVE / TEMPO-MATCHED MUSIC — ✅ feasible now via STEM-SWAPPING (HIGH, 3-0)
Real-time cadence-matched, mood-adaptive music is a **proven, phone-deployable pattern** —
*adapt/remix pre-built stems live*, don't generate from scratch.
- **Weav Run:** detects running cadence via the phone accelerometer and instantly matches an
  adaptive track's BPM across **100–240 BPM**, keeping every footfall on a beat. Tracks are
  built from **stems coded to trigger on input values** → the engine swaps stems live for a
  real-time remix responding to cadence/energy. (Women's Running, Intl Sound Directory, TechCrunch.)
- **US Patent 11,690,535 (BeatHealth/BeatRun):** clinically-tested inertial-sensor→smartphone
  loop manipulating music's rhythm in real time to guide cadence — a working sensor-to-audio
  loop on a phone.
- **Workaround / v2 line:** **fully-generative real-time music** (Suno, Udio, Google Lyria,
  Mubert, MusicGen, Stable Audio, ACE-Step) was **NOT confirmed as real-time-interactive** —
  those remain largely **offline → v2**. Mechanism for v1 (phase-vocoder time-stretch + stem
  gating) is standard and reproducible. Caveat: Weav is a 2017–2020 product; mid-2026
  availability uncertain, but the *technique* is what matters and it's replicable.
- Sources: medium.com/@weavmusic, USPTO patent 11690535.

## 3. SOUNDSCAPES / AMBIENCE (crowd, woods, sea, stadium, rain) — ✅ feasible now (HIGH, 3-0)
- **ElevenLabs text-to-sound-effects API** (`eleven_text_to_sound_v2`,
  `/v1/text-to-sound-generation`): natural-language → high-quality SFX, **48kHz, 0.5–30s per
  clip**, with control over timing/style/complexity, and a **seamless LOOP option** (blends end
  into start with no gap). So a ~30s "soft rain"/"nature ambience"/"stadium crowd" generation
  **loops endlessly** into a continuous atmospheric bed. Explicitly positioned for
  film/games/ambient. Directly covers the whole worlds layer.
- Open: Meta AudioGen, Stable Audio (from brief; not the surviving-claim subject).
- Source: elevenlabs.io/docs sound-effects.

## 4. SPATIAL / 3D "RUNNING WITH A PACK" AUDIO — ✅ feasible now, ON-DEVICE, FREE (HIGH, 3-0)
The "crowd/pack around you" 3D effect runs **on-device with mature open Apache-2.0 engines** —
no cloud, no license cost.
- **Steam Audio (Valve):** open-source **Apache-2.0** (free commercial), binaural/HRTF, **iOS +
  Android** (armv7/arm64/x86/x64), integrates with Unity/Unreal/FMOD/Wwise.
- **Resonance Audio (Google):** fully open-source **Apache-2.0**, full C++ source,
  Unity/FMOD/Wwise/DAW integrations, Android/iOS toolchains. Low-maintenance/legacy but intact.
- **Caveat:** both are games/VR-oriented → using in a plain phone app needs native C-API
  integration effort. Closed alts (Apple Spatial Audio, Dolby Atmos) exist but weren't the
  surviving-claim subject.
- Sources: valvesoftware.github.io/steam-audio, resonance-audio.github.io.

## 5. REAL-TIME SENSOR-DRIVEN ORCHESTRATION on a phone — ✅ feasible now (HIGH, 3-0)
Mixing the layers live and adapting to HR / pace / mood is demonstrably buildable on-device.
- The interactive-audio **middleware model (FMOD, Wwise)** — mirrored by the open Steam/
  Resonance integrations — gives a concrete path to layered adaptive mixing.
- The **BeatHealth patent + Weav stem-swapping** independently confirm a working real-time
  accelerometer→audio loop on a smartphone, **generalizable from cadence to HR/mood**.
- Sources: steam-audio, resonance-audio, USPTO 11690535, weavmusic.

## 6. MOTION-CORRECT EXERCISE-DEMO VIDEO — ✅ viable now (HIGH, 3-0) — newest frontier
Transfer *real* form from a reference clip (not hallucinate it). Open source ≈ commercial
parity for short clips.
- **Kling-MotionControl (closed, arXiv 2603.03160):** transfers motion dynamics from a real
  driving video onto a reference image — subject faithfully mimics body/face/hand movement.
  Motion-conditioned, not hallucinated. (Self-reported.)
- **Wan-Move (OPEN, Alibaba Tongyi Lab, NeurIPS 2025, Apache-2.0, weights on HF/GitHub/
  ModelScope):** **5s 480p** clips, motion-control accuracy **on par with Kling 1.5 Pro Motion
  Brush** (user-study win ~50–53%); supports motion transfer + 3D object rotation via latent
  trajectory guidance.
- **Honest limits:** clips are **short (5s) and 480p** → full demos need stitching/upscaling. A
  claim that Wan-Move uses joint-level body/face/hand representations for *exercise-grade form
  fidelity* was **REFUTED (1-2)** → rep-count/form fidelity beyond short clips is **unproven**.
  Core motion-transfer mechanism is solid. **Workaround:** short motion-conditioned clips from a
  real trainer reference + your dad/sports-science verification gate (already planned, F.8b).
- Sources: arxiv 2603.03160, neurohive Wan-Move, huggingface Wan-Move-14B-480P.

## 7. VIDEO SEGMENTATION (full workout video → timestamped exercises) — ✅ feasible now (HIGH, 3-0)
- **Gemini 2.5 Pro:** segments video into discrete **timestamped events** from combined
  audio+visual cues (16 segments in a 10-min video in Google's demo); answers MM:SS queries,
  temporal reasoning/moment-retrieval (rivals fine-tuned models on QVHighlights).
- **Caveats:** demo was product-presentations not exercises (sound but untested extrapolation),
  vendor-published, second-level precision with imperfections → **expect a human-review pass on
  segment boundaries.**
- Source: developers.googleblog.com Gemini 2.5 video understanding.

---

## PUTTING IT TOGETHER — v1 architecture (MEDIUM confidence; 2 infra claims refuted)
Clean **on-device vs cloud** split:
- **On-device:** spatial binaural (Steam/Resonance), real-time cadence detection + stem-swap
  music (Weav/BeatHealth pattern), the sensor-orchestration loop, cached ambience loops.
- **Cloud:** low-latency streaming coach voice (Cartesia/ElevenLabs/OpenAI Realtime),
  pre-generated motivational + motion-transfer demo videos (Kling/Wan-Move), pre-baked
  ElevenLabs ambience (cached locally).

**v1 (buildable now):** streaming coach voice + looped generative ambience + on-device spatial
+ stem-based adaptive music + pre-rendered motion-transfer demos + Gemini segmentation.
**v2 (near-future):** fully real-time *generative* music, and longer high-fidelity form-correct
demo video.

## ⚠️ REFUTED — do NOT assume these (measure them yourself)
1. "$0.03/min for a full voice pipeline at scale" — **REFUTED 0-3.** Per-session cost UNKNOWN.
2. "Sub-500ms global end-to-end latency achievable today" — **REFUTED 1-2.** Guaranteed global
   latency UNKNOWN.
3. "Wan-Move has joint-level form fidelity" — **REFUTED 1-2.** Exercise-grade form fidelity UNPROVEN.

## The 2–3 hardest pieces + the workarounds
1. **Fully real-time generative music** → not proven real-time; **use live stem-adaptation** (v1), generative later (v2).
2. **Long, high-fidelity, form-CORRECT demo video** → **short 5s motion-transfer clips + human (dad/sports-sci) verification** (F.8b), stitch/upscale as needed.
3. **Per-session cost + true end-to-end latency** → **unknown; prototype and measure**, don't budget on headline numbers.

## Open questions to resolve by measurement/testing
- Actual measured per-session cost + true end-to-end latency of the assembled stack, and at scale.
- Which TTS vendor gives the best expressive **voice-CLONE** quality for dad's voice + the consent/licensing path.
- Can any generative-music tool run real-time/interactive (not offline), and under what commercial license.
- How well motion-transfer preserves **correct form** beyond short clips; path to full-length demos.

## RECOMMENDED v1 STACK (assemble now)
- **Coach voice:** Cartesia/ElevenLabs streaming TTS (or OpenAI Realtime-2) — you already run OpenAI Realtime.
- **Ambience:** ElevenLabs sound-effects API → pre-bake looping beds per "world," cache on-device.
- **Spatial:** Steam Audio (Apache-2.0) on-device for the pack/crowd effect.
- **Adaptive music:** stem-based engine, cadence→BPM (Weav/BeatHealth pattern), on-device. License stems commercially.
- **Demo videos:** Wan-Move (open) or Kling-MotionControl (closed), motion-driven from a real trainer clip, short + verified (F.8b).
- **Segmentation:** Gemini 2.5 Pro → timestamped exercises, human-review boundaries.
- **Orchestration:** FMOD/Wwise-style layered mixer driven by HR/pace/mood.

## Full source list (quality-rated)
Primary/strong: elevenlabs.io/docs (sound-effects), valvesoftware.github.io/steam-audio,
resonance-audio.github.io, USPTO patent 11690535, NeurIPS/HF Wan-Move, developers.googleblog.com
(Gemini 2.5), arxiv 2603.03160 (Kling-MotionControl), openai.com.
Vendor-adjacent blogs (corroborated): coval.ai, inworld.ai, neurohive.io, medium.com/@weavmusic.
Filtered as unreliable (0 surviving claims): gradium.ai, futureagi.com, presenc.ai,
localaimaster.com, cerebrium.ai (the two refuted cost/latency claims came from here).

---
*Deep-research run wf_903584ba-dc1, 2026-07-20. Mid-2026 snapshot; re-verify fast-moving numbers before committing.*
