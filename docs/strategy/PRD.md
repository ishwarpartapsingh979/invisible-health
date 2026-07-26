# Invisible Health — PRD (canonical)

> The source-of-truth product spec. Shared by laptop + mobile/cloud Claude Code sessions.
> Read together with `CURRENT-STATE.md` (status/plan) and `EXECUTION-STRATEGY.md` (how agents run).
> A Google-Docs-friendly version with rendered tables lives at repo root `prd-features.html`.

---

## Press Release
Ishwar today released a health **experiences** app backed by his dad's 40+ years of fitness
coaching experience and sports-science principles (incl. 1 year as fitness coach of the Punjab
Cricket Ranji Trophy team — Yuvraj Singh, Harbhajan Singh). It's for people like Ishwar: a
Bangalore corporate employee with a high-stress job who has 1–2 hrs/day for workouts.

Ishwar doesn't trust ChatGPT/Claude/Gemini for workouts — they lack full context — so his dad
plans them. But he isn't consistent: workouts are boring, especially after a high-stress day,
and the same music gets stale in 10–14 days. You can't hand a new workout every day (sports
science demands staying on sets before ramping). Personal training works (someone waits for you;
you've paid) but is expensive (~₹1K/session). The form-coaching matters but is largely on YouTube.

Workouts have **no short-term deadline**, so they lose to short-term work pressures — reactive,
not proactive. Yet **group classes thrive** (Cult full; SoulCycle famous until trainer/cost
issues). Why: real-time guidance (no decisions to make), fits your time, and a **sensory
experience** — coach talking/motivating, the workout's positivity, **music**, the **vibe** of
the room, people around. Their drawbacks: **not personalised**, and **slot/availability** pain.

**The thesis:** combine the **hyper-personalisation of personal training** × the **sensory
experience of group classes**, delivered **voice-first**.

What we provide:
- **Individual fitness (running / functional / gym):** workouts designed by a pro-athlete coach
  (40+ yrs), hyper-personalised to how much time you have, with a **video per exercise**. Default
  **60 min**, but you **chat to tailor** it to your time/motivation. A mix of **music + real-time
  coach + a vibe** (underground/forest party sound effects…) as a **sensory audio experience**,
  adapted live to **motivate more / hold / ramp down**.
- **Steps goal:** help hit the goal via **tailored audio experiences built around the steps left**.
- **Meditative (low priority):** sensory audio meditations before sleep.
- Plus a **visual experience for AI-glasses** users, on top of the audio.

## Users
- **User #1:** individual fitness (running, functional training, gym). *(primary)*
- **User #2:** fitness goal = **# steps**. *(low-friction wedge)*
- **Low priority:** meditative experiences (already served by meditation apps).

## Roadmap — **TBD (to be finalised next week)**
> **Status: PLACEHOLDER — not yet decided.** Ishwar owns the MVP scope + which users to target
> first. He is reading the PRD over the week and will draw the MVP line himself; this section
> gets filled in next week.
>
> - **MVP (v1) — for Ishwar + Uday + Jasmine:** _TBD_
> - **Fast-follow:** _TBD_
> - **Beyond / later:** _TBD_
>
> When finalising, the reference material is in this doc: feature **priorities + integrations**
> are in the Feature Summary; the two build dependencies are called out at the end
> (**structured-workout model** = the linchpin; **HealthKit steps** = unlocks the Steps wedge).

## Core UX principle (do not drift)
**Voice is THE interface.** Minimise screens. The app asks and confirms **by voice**, and stores
answers into the relevant tabs (Profile / Workout / History). Buttons are the exception, only
where you're genuinely looking (browse experiences, review history, settings). Once a session
starts, the phone is **pocketed** — everything is AirPods audio; tracking is on the watch/Whoop.
**Onboarding is ONE voice screen** — the coach interviews you conversationally and files the
answers; NOT a multi-step form. (Next-weekend UI overhaul: collapse remaining screens toward this.)

## CUJs (Critical User Journeys)
All interactions are **multimodal (voice, text, picture)**.

**Entry (shared):** first open shows a sign-in screen — **"Sign in with Apple"** is the primary,
encouraged action ("save your progress & sync"); a clear **secondary "Continue without login."**
Never forced. Continue-without-login → start **anonymously**; everything you build (incl. linking
**Apple Health with one tap** — a system permission, not a login) is yours on-device until you
choose to sign in, when it **all transfers** (and syncs). If you never sign in, it still works and
**survives reinstall**. Signing into an account with existing data keeps the account + folds in
what makes sense.

**User #1 — Fitness.** The app should know my fitness level, goals, workouts I love/dislike,
facilities/equipment, motivators; my **music taste** (Apple Music/Spotify); real-time **HR**
(Whoop/Apple Watch). Each morning I get a **60-min** workout with a **gist + videos**; I can
**interact to adjust** to my state; a **hype video** is made daily from my context + past
workouts. When I start: the coach talks based on my context; I **control it** (speed up the
intro / skip to the exercise); it **silently monitors HR**, occasionally asks how I feel and
takes my answer; when I say I'm starting an exercise the **video is ready**; it tracks **HR per
exercise**, times exercises + rests; **motivates at intervals, not too much**; everything the
coach says is **intertwined with music + vibe**, which I can **control or stop** by voice;
**cool-down** is scheduled and the coach's tone changes; at the end it gives a **full breakdown**
(every exercise, HR, indicators) + ending motivation; I can **see the whole chat**; and all of it
**feeds the model** to tailor my workouts, music, vibes, and coach.

**User #1 — bring their own workout.** I already have a workout (trainer / program / app / my
own) and want *your experience* on *my* plan. I tell you about it — **voice, text, photo, or
screen-recording** — a little or a lot. You may ask for more (to time it tighter) but **never
block** me: rich detail → precise timing/HR/videos/cool-down; sparse ("legs, ~45 min") → you fill
from what you know + typical patterns. You **save it** (reuse/tweak — "same as last week, swap
deadlifts"); you may **flag risk** (subjective wins) but **don't override** — my plan stays mine.
Then I get the **full experience wrapped around my workout**, and you **learn my routines** over time.

**User #2 — Steps.** The app should know my **personalised step goal** (not blanket 10k, adaptive),
my level/motivators/when-I-walk/routes, my music taste, and real-time steps (Apple Health/Google
Fit), HR, pace+distance (GPS). **Passively** it takes my step count and, on app-open (pull, never
a guilt-ping), tells me my **gap** warmly and **offers a delightful way to close it** ("1,500 to
go → a 12-min beach wind-down walk"). When I walk (accept, or "let's walk," or "20 min, calm me
down"), the coach builds an experience calibrated to **steps-left + time + mood** and starts on my
context; I **control** it (vibe/music/shorter/"just walk quietly"). During: it **paces me to hit
the target in my time**, tracks steps/pace/HR, asks how I feel, **feel-good milestones** (never
"you're behind"), music+vibe adapting (energize/maintain/wind-down), voice-controlled, phone
pocketed. Finish: **celebration** + afterglow; missing is **shame-free** ("7,200 today, nice —
want a short one this evening?"); a **recap** (steps/distance/pace/HR/streak) + calm ending. After:
I see the whole chat; everything **feeds the model** to tune my goal/experiences/music/vibes.

---

## FEATURE SUMMARY
**The product:** the hyper-personalization of a personal trainer × the sensory pull of a group
class, voice-first. **Priority = how central it is to why the user uses the app** (the experience
*is* the product → P0 even where hardest to build). **User #1 (Fitness) primary; User #2 (Steps)
the wedge; meditative low.**

### Foundational — shared by all
| Feature | What it delivers | Pri | Key integrations |
|---|---|---|---|
| Frictionless Start | Login-first (Sign in with Apple) + secondary "Continue without login"; anon profile; link Apple Health without login; sign in anytime → transfers + syncs. | P0 | Sign in with Apple · HealthKit · Supabase (/claim) · Keychain |
| Multimodal Everywhere | Every interaction by voice, text, or picture. | P0 | LiveKit + OpenAI Realtime · Gemini (vision) |
| Knows You (context) | Level, goals, loves/dislikes, equipment, motivators; music taste; live biometrics. | P0 | HealthKit · Whoop · MusicKit/Spotify · Supabase |
| The Vibe (adaptive sensory audio) | Coach voice intertwined with music + a vibe, adapting push/hold/ramp-down; voice-controlled. | P0 | ElevenLabs · stem music + CoreMotion · Steam Audio · LiveKit |
| Music (their taste) | Their Apple Music/Spotify soundtrack, sequenced + adapted to the session. | P0 | Apple MusicKit · Spotify SDK/Web API |
| Deliver-with-what-we-have (principle) | Always give value from what we know; ask only to sharpen, never to gate. | P0 | — |
| Pro-Coach Backing (trust) | Grounded in a real pro-athlete coach's system — the "why not ChatGPT." | P0 | Supabase rules engine |
| Gets Smarter (memory/learning) | Full searchable coach chat; everything feeds the model → tailors workouts, music, vibes, coach. | P1 | Supabase (user_facts) · Langfuse |
| Exercise Video Library | A demo clip for every exercise, mapped from any workout to a **licensed** provider we host; we don't store/recreate others' clips. | P0 | licensed exercise-video provider/API · built-in exercise DB (fallback) · Gemini (name match) |

### Admin / Content — behind the scenes
| Feature | What it delivers | Pri | Key integrations |
|---|---|---|---|
| Admin: Reference Workout Ingestion | Admin uploads reference training recordings (e.g. Nike Training Club); system extracts the **workout structure + coaching approach (not the video)** into our DB as templates/knowledge that inform coach-authored sessions. Admin-only. | P0 | Gemini (video understanding) · Supabase (templates/knowledge) · Show Me capture |

### User #1 — Fitness (primary)
| Feature | What it delivers | Pri | Key integrations |
|---|---|---|---|
| Your Daily Session | Pro-coach 60-min workout, gist, video per exercise (from the Exercise Video Library); chat to tailor. | P0 | Supabase · Gemini · Exercise Video Library (licensed) |
| The Coach (real-time) | Context start; you control it; silent HR + check-ins; video on "starting X"; times exercises + rests; per-exercise HR; earned/not-too-frequent motivation; cool-down shift. | P0 | LiveKit + OpenAI Realtime · Whoop/Apple Watch |
| Bring Your Own Workout | Tell us your plan (voice/text/photo/screen-recording); progressive, non-blocking detail; saved/reusable; vet-not-override; wrapped in the full experience. | P1 | Gemini vision · Show Me capture · LiveKit+Realtime · Supabase |
| Hype Film | Short video generated daily from context + past workouts to get you starting. | P1 | video-assembly (TTS+music+visuals) · Supabase |
| The Wrap (recap) | Every exercise, HR + indicators, progress + ending motivation. | P1 | Supabase · Whoop/HealthKit |

### User #2 — Steps / Walk (wedge — ships earliest)
| Feature | What it delivers | Pri | Key integrations |
|---|---|---|---|
| Your Step Goal | Personalized, adaptive target (not blanket 10k). | P0 | HealthKit/Health Connect · Supabase |
| All-Day Gap Tracking | Passive count, works signed-out; always knows the gap; pull-not-push on open. | P0 | HealthKit / Health Connect (Google Fit) |
| Gap-Close Offer | A delightful walk calibrated to steps + time + mood — invite, never shame. | P0 | LiveKit+Realtime · ElevenLabs · MusicKit |
| Walk Coach | Paces you to hit the target in your time; live steps/pace/HR; feel-good milestones; full voice control. | P0 | CoreLocation/GPS · HealthKit · Whoop · LiveKit+Realtime |
| Finish & Streak | Celebration; shame-free miss + top-up; recap + streak. | P0 | HealthKit · Supabase |

### Future / low
| Feature | What it delivers | Pri | Integrations |
|---|---|---|---|
| Wind-Down / meditative | Evening sensory audio → Sleep Focus hand-off. | P3 (low) | App Intents/Shortcuts · Core Haptics · ElevenLabs |
| Visual Layer | The vibe you hear, on AI glasses. | P3 | AI-glasses SDK |

## FEATURE DETAILS
See `prd-features.html` (repo root) for the full, formatted detail per feature (What / How /
IP boundary / Integrations / Acceptance). Key call-outs:
- **Exercise Video Library** — normalize each exercise name → licensed provider clip (host it);
  fallback to built-in exercise DB / still + cue. **IP: license + host demos; never store,
  redistribute, or AI-recreate copyrighted clips.** Verify the provider license permits
  (a) storing files and (b) redistribution in a commercial app. Own filmed footage later (moat).
- **Admin: Reference Workout Ingestion** — extract **structure/metadata only** (exercises, sets,
  rest, cues, progression) as reference the coach designs from; **source video is never stored/
  served**; each exercise's demo comes from the licensed library. Reference to inform **original**
  coach-authored workouts, not 1:1 clones.

## Two build anchors
1. **The P0 gap is the Vibe stack + music playback** (ElevenLabs · adaptive music/CoreMotion ·
   Steam Audio · MusicKit/Spotify) — the integrations that create the *experience*. Brain/
   transport/data/biometrics/vision are already built.
2. **The structured-workout model** is the recurring linchpin (daily session · per-exercise
   HR/timing · recap · bring-your-own) — build it first; and **HealthKit steps** unlocks the
   entire Steps wedge (so it can ship earliest).
