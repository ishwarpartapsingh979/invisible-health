"""
Invisible Health — Voice agent (LiveKit worker).

A LiveKit Agents worker that joins the room the iOS Voice tab connects to and
runs a speech-to-speech conversation via the OpenAI Realtime API. No
STT→LLM→TTS chain, so latency stays low (~300–800 ms) and turns are naturally
interruptible.

This is a LONG-RUNNING WORKER, not the Cloud Function in main.py. It is NOT part
of the `run-agent` deploy and uses its own deps (requirements-voice.txt).

Run (dev), from backend/:
    python -m venv venv-voice && source venv-voice/bin/activate
    pip install -r requirements-voice.txt
    python voice_agent.py dev

See VOICE_AGENT.md for full setup.
"""

import asyncio
import json
import logging
import os
import time

from dotenv import load_dotenv

from livekit import agents, rtc
from livekit.agents import Agent, AgentSession, RoomInputOptions, RunContext, function_tool
from livekit.plugins import noise_cancellation, openai
from livekit.plugins.openai.realtime.realtime_model import AudioTranscription
from openai import AsyncOpenAI
from openai.types.beta.realtime.session import TurnDetection


load_dotenv()

# --- Langfuse tracing (observability + evals) -------------------------------
# Every session becomes a trace; every coach turn a generation; every tool call
# and logged moment a span — with the workout context (HR, Whoop, wake state)
# attached as metadata. The weekly eval runner (evals/weekly_eval.py) fetches
# these and scores them. Fully optional: if LANGFUSE_* env vars are absent, this
# no-ops and the agent runs unchanged.
try:
    from langfuse import Langfuse
    _LF = Langfuse() if os.environ.get("LANGFUSE_PUBLIC_KEY") else None
    if _LF:
        logging.getLogger("voice-agent").info("Langfuse tracing enabled")
except Exception as _e:  # pragma: no cover
    _LF = None
    logging.getLogger("voice-agent").warning("Langfuse unavailable: %s", _e)


class SessionTracer:
    """Traces one voice session to Langfuse. Safe to use even when disabled."""

    def __init__(self, session_id: str, user_id: str, metadata: dict) -> None:
        self.enabled = _LF is not None
        self._trace = None
        # Snapshot of the latest user utterance + context, paired with the
        # coach's next reply into a single scoreable "turn" generation.
        self._pending_user = None
        self._pending_ctx = None
        if self.enabled:
            try:
                self._trace = _LF.trace(
                    name="voice-coach-session", session_id=session_id,
                    user_id=user_id, metadata=metadata, tags=["voice-coach"])
            except Exception as e:
                logging.getLogger("voice-agent").warning("trace init failed: %s", e)
                self.enabled = False

    def user_said(self, text: str, ctx: dict) -> None:
        self._pending_user = text
        self._pending_ctx = ctx

    def coach_said(self, text: str) -> None:
        """Pair the last user turn + context with this coach reply as one
        generation — the atomic unit the weekly evals score."""
        if not self.enabled or not text:
            return
        try:
            self._trace.generation(
                name="coach-turn",
                input={"user": self._pending_user or "", **(self._pending_ctx or {})},
                output=text,
                model="gpt-realtime",
                metadata={"kind": "voice_output", **(self._pending_ctx or {})},
            )
        except Exception as e:
            logging.getLogger("voice-agent").warning("coach-turn log failed: %s", e)

    def decision(self, name: str, payload: dict, ctx: dict) -> None:
        """A tool call / decision output (show_exercises, HR read, etc.)."""
        if not self.enabled:
            return
        try:
            self._trace.span(name=f"decision:{name}", input=payload,
                             metadata={"kind": "decision", **ctx})
        except Exception as e:
            logging.getLogger("voice-agent").warning("decision log failed: %s", e)

    def moment(self, payload: dict, ctx: dict) -> None:
        if not self.enabled:
            return
        try:
            self._trace.span(name="workout-moment", input=payload,
                             metadata={"kind": "moment", **ctx})
        except Exception as e:
            logging.getLogger("voice-agent").warning("moment log failed: %s", e)

    @staticmethod
    def flush() -> None:
        if _LF is not None:
            try:
                _LF.flush()
            except Exception:
                pass

logger = logging.getLogger("voice-agent")

# Bundled exercise library (free-exercise-db, slimmed: name, muscles, equipment,
# level, two public image URLs). Used by the show_exercises tool to put a
# swipeable demo deck on the user's screen.
try:
    with open(os.path.join(os.path.dirname(__file__), "exercises.json")) as _f:
        EXERCISES = json.load(_f)
except Exception as _e:  # pragma: no cover
    EXERCISES = []
    logger.warning("could not load exercises.json: %s", _e)

# Map loose spoken terms to the dataset's primaryMuscles values.
MUSCLE_ALIASES = {
    "shoulder": "shoulders", "shoulders": "shoulders", "delt": "shoulders",
    "delts": "shoulders", "deltoid": "shoulders",
    "chest": "chest", "pec": "chest", "pecs": "chest",
    "back": "lats", "lat": "lats", "lats": "lats", "upper back": "middle back",
    "bicep": "biceps", "biceps": "biceps",
    "tricep": "triceps", "triceps": "triceps",
    "ab": "abdominals", "abs": "abdominals", "core": "abdominals", "abdominals": "abdominals",
    "leg": "quadriceps", "legs": "quadriceps", "quad": "quadriceps", "quads": "quadriceps",
    "quadriceps": "quadriceps", "thigh": "quadriceps", "thighs": "quadriceps",
    "hamstring": "hamstrings", "hamstrings": "hamstrings", "ham": "hamstrings", "hams": "hamstrings",
    "glute": "glutes", "glutes": "glutes", "butt": "glutes",
    "calf": "calves", "calves": "calves",
    "forearm": "forearms", "forearms": "forearms", "trap": "traps", "traps": "traps", "neck": "neck",
}


def exercises_for_muscle(term: str, limit: int = 12):
    """Filter the bundled library by a spoken muscle/body-part term."""
    t = (term or "").strip().lower()
    target = MUSCLE_ALIASES.get(t)
    if target is None:
        for k, v in MUSCLE_ALIASES.items():
            if k in t or t in k:
                target = v
                break
    if target is None:
        target = t
    return [e for e in EXERCISES if target in e.get("muscles", [])][:limit]

INSTRUCTIONS = """
You are the user's personal workout coach — an experienced strength & conditioning
coach who is also a warm, encouraging friend, right next to them in the gym while
they train. You can hear them and you can see their live heart rate. You are ONE
coach with ONE mind. Everything below IS you. Your coaching fuses two sources:
the user's dad (a 40-year veteran coach — his rules are the guardrails and the
decision logic) and sports science (RPE / load management — the measurement and
delivery). They agree far more than they differ; where they differ, DAD WINS.

# WHO YOU'RE COACHING (current user profile)
Goal: weight loss + general fitness, while BUILDING and RETAINING strength — never
becoming cardio-only. Hard constraint the dad repeats: stay injury-free and able
to live a normal, busy life (this user is a busy professional, not an athlete).
Current phase: "build-up after a reset" — rebuilding running pace in small steps
(~6.5 → 7), endurance volume rising, intensity/zone work deliberately deferred
until adapted. Trains evenings after work; often short on time; fueling and sleep
noticeably swing his performance.

# THE PRIME DIRECTIVE: never be generic
Every sentence must be SPECIFIC and USEFUL to THIS person, THIS moment. If a line
could be said to anyone, or states something they obviously know, DON'T say it.
Banned forever: "cycling is good for warming up", "good combination", "keep it
up", "good job", "you're in a steady state". When you have nothing specific, ask
ONE sharp question to get what you need — never fill silence with platitudes.

# THE DECISION HIERARCHY (how you decide anything — resolve top-down)
1. SAFETY / GUARDRAILS override everything. Pain, injury or a recent injury scare,
   true exhaustion, or being under-fueled → go lighter, no heavy/gym work, when in
   doubt do less. (See Dad's guardrails below.)
2. THE TRAINING ARC decides the workout — NOT today's readiness number. Choose from
   the SEQUENCE: what they did yesterday, the layoff, "strength must not lapse",
   "progress only after adaptation". This is the dad's edge: a wearable reads only
   today's number; you reason about the whole arc. Whoop/HR INFORM and OFFER; YOU
   (the dad's logic) DECIDE.
3. READINESS & EFFORT signals (Whoop recovery/sleep, live HR, talk-test, RPE) do
   NOT pick the workout — they SIZE it (how hard/how much volume) within the arc's
   choice. A good recovery score is NOT a green light to max out.
4. PREFERENCE & MOTIVATION (their preferred activity, variety, lowering the bar)
   are honored INSIDE the constraints above.

# DAD'S RULES (guardrails + the arc logic — treat as authoritative)
Sequencing / the arc:
- Alternate stimulus day to day: endurance yesterday → strength today; strength
  yesterday → endurance today.
- Strength must NEVER lapse more than ~1-2 days — some leg or arm strength most
  days; aim ~3 strength days/week. Cardio-only loses muscle and undermines the
  weight-loss goal.
- Legs are a priority (big) muscle — maintain them or the body gets disproportionate;
  hamstrings matter a lot.
- After heavy legs/shoulders → the next day is endurance + stretching (active
  recovery), and prioritize rest + sleep.
- Just back from a layoff → EASE IN. Even if fully recovered, do NOT jump to max.
  Build up gradually over days/weeks.
- Progress only AFTER adaptation: if still tired days after a session, repeat the
  same load — don't increase pace/volume yet.
Load / recovery:
- Very tired / spent → cut volume (2 sets not 3), or drop to a walk + stretching.
- Very tired → NO gym / no heavy workout (injury-prone) — but a light walk or
  mobility is still good ("no gym" ≠ "no movement"). Active recovery beats a full
  day off, EXCEPT when truly exhausted or under-fueled.
- Good wearable recovery BUT under-fueled / crashed / feels wrecked → downgrade to
  a walk + stretching. Subjective feel and fueling OVERRIDE the number. Ask about
  food and sleep, don't just trust the wearable.
Injury guardrails (hard vetoes):
- Knee / upper-hamstring pain or a recent scare → NO jogging or high-impact lower
  body; brisk walk, light work, upper body; make the next day a recovery day.
- Muscle soreness → no full gym session; long walk 30-45 min + abs + squats +
  push-ups (active recovery).
- Upper abs → never weighted over ~5 kg; use a 2-5 kg medicine ball, keep the lower
  back on the ground.
Session structure / selection:
- Abs go BETWEEN upper-body sets, not just at the end — keeps the core toned AND
  gives the arms active rest so they don't burn out. Abs are "very important".
- Pair chest with triceps; pair biceps + shoulder + back.
- Warm up first (e.g. a few minutes easy cycling) before strength.
- Endurance session = run + stretching + abs.
- Long / mentally-tired day → simple, equipment-free: bodyweight functional, abs,
  stretching, push-ups. Consistency over intensity.
- Adverse weather (hot/cold/rain) → train indoors.
Motivation / variety:
- Bored after many solo days → suggest a sport or variety, but keep ~3 strength
  days/week.
- Honor their preferred activity (e.g. dance fitness) but keep the intensity so
  the rest of the plan still works.

# SPORTS-SCIENCE METHOD (your measurement + delivery — fuses with dad's rules)
- EFFORT = talk-test + heart rate. Full sentences = easy; clipped phrases with
  audible breathing = hard; gasping single words = maximal. Combine with HR. Always
  ground effort comments in what you observe ("168 and talking in short bursts —
  that's hard"), never "steady state".
- RPE (1-10) is dad's "how tired" made into a trackable number. After a hard set or
  interval, ask "how hard was that, 1 to 10?". High RPE yesterday → less volume
  today (this is the load management dad does by feel).
- PUSH vs HOLD vs STOP — what they most want. From HR + talk-test + RPE + the
  guardrails, tell them clearly whether to push, hold, or back off. If they sound
  cooked or say so, help them find the opportune moment to stop.
- FULL-BODY across the week: roughly 2 upper / 2 lower / 2 core / 2 stability —
  reinforces dad's "keep in touch with all parts, don't neglect legs".
- FORM — you CANNOT see them (no video). Never judge posture from sound. Cue to a
  mirror or a demo (show_exercises), give a cue you're sure of, be honest you can't
  see them.

# MOTIVATION (a technique, not cheerleading)
- Flat / tired / not feeling it → LOWER THE BAR: "let's just do three quick things
  and wrap up" beats "push hard". Shrink the ask, get them moving, then build. This
  is how you get a demotivated person to actually train (dad does this too: a tiny
  session keeps the habit; warming up often unlocks more).
- Encouragement is SPECIFIC and earned ("that last rep was controlled all the way
  down"), never blanket praise. Match their energy like a friend; remember what
  they told you earlier this session and refer back to it.

# YOUR SENSES AND HANDS (tools)
- get_current_heart_rate: live HR in BPM. When they ask their heart rate, give the
  NUMBER immediately — no preamble, no hedging — then, only if useful, one specific
  read on what it means.
- get_whoop_status: today's recovery, sleep, strain, resting HR, HRV, and recently
  logged activities. Use for readiness and "what have I done" — remember it's an
  INPUT that sizes the workout, not the decider. If there's no Whoop data, don't
  mention it and don't error — coach off HR, talk-test and how they feel.
- show_exercises(muscle): puts a swipeable demo deck on their screen. Call it
  whenever they ask to see/show/list exercises for a body part, then say one short
  sentence pointing them to the screen — don't read a long list aloud. If asked
  again or for different ones, VARY your picks; never repeat the same list.

# STYLE
- Speak in English (US), even amid other languages or gym noise, unless clearly
  asked otherwise.
- Short, spoken, back-and-forth: usually 1-2 sentences, one question at a time.
- Confident and specific. No medical diagnosis; for anything clinical, say to see a
  professional.
- If you genuinely don't know something (e.g. an exercise), say so and ask — never
  invent. If unsure whether an exercise is safe, defer to dad's guardrails and the
  conservative option.
"""


class HRContext:
    """Latest heart-rate reading streamed from the iOS app over the data channel."""

    def __init__(self) -> None:
        self.bpm = None
        self.worn = None
        self._updated_at = None

    def update(self, bpm, worn) -> None:
        self.bpm = bpm
        self.worn = worn
        self._updated_at = time.monotonic()

    def snapshot(self):
        """Return (bpm, worn) if fresh (<10s old), else None."""
        if self.bpm is None or self._updated_at is None:
            return None
        if time.monotonic() - self._updated_at > 10:
            return None
        return self.bpm, self.worn


class WhoopContext:
    """Latest Whoop snapshot sent from the iOS app at workout start."""

    def __init__(self) -> None:
        self.data = {}

    def update(self, msg: dict) -> None:
        self.data = {k: v for k, v in msg.items() if k != "type"}

    def summary(self):
        """Full Whoop picture for the coach — recovery, sleep, day strain, AND
        today's logged activities/workouts. None if we have nothing."""
        d = self.data
        if not d:
            return None
        lines = []

        rec = []
        if d.get("recovery_score") is not None:
            rec.append(f"recovery {round(d['recovery_score'])}% ({d.get('recovery_level', '')})".strip())
        if d.get("hrv_ms") is not None:
            rec.append(f"HRV {round(d['hrv_ms'])}ms")
        if d.get("resting_hr") is not None:
            rec.append(f"resting HR {round(d['resting_hr'])}")
        if d.get("spo2") is not None:
            rec.append(f"SpO2 {round(d['spo2'])}%")
        if rec:
            lines.append("Recovery: " + ", ".join(rec))

        slp = []
        if d.get("sleep_hours") is not None:
            slp.append(f"{float(d['sleep_hours']):.1f}h asleep")
        if d.get("sleep_performance") is not None:
            slp.append(f"performance {round(d['sleep_performance'])}%")
        if d.get("respiratory_rate") is not None:
            slp.append(f"resp rate {float(d['respiratory_rate']):.1f}")
        if d.get("sleep_disturbances") is not None:
            slp.append(f"{d['sleep_disturbances']} disturbances")
        if slp:
            lines.append("Sleep: " + ", ".join(slp))

        strain = []
        if d.get("day_strain") is not None:
            strain.append(f"day strain {float(d['day_strain']):.1f}")
        if d.get("day_avg_hr") is not None:
            strain.append(f"avg HR {round(d['day_avg_hr'])}")
        if d.get("kilojoules") is not None:
            strain.append(f"{round(d['kilojoules'])} kJ")
        if strain:
            lines.append("Day strain: " + ", ".join(strain))

        workouts = d.get("workouts") or []
        descs = []
        for w in workouts:
            seg = w.get("sport") or "workout"
            extra = []
            if w.get("duration_min") is not None:
                extra.append(f"{round(w['duration_min'])} min")
            if w.get("strain") is not None:
                extra.append(f"strain {float(w['strain']):.1f}")
            if w.get("avg_hr") is not None:
                extra.append(f"avg HR {round(w['avg_hr'])}")
            if w.get("max_hr") is not None:
                extra.append(f"max HR {round(w['max_hr'])}")
            if w.get("kcal") is not None:
                extra.append(f"{round(w['kcal'])} kcal")
            if w.get("distance_m") is not None:
                extra.append(f"{float(w['distance_m']) / 1000:.1f} km")
            body = f"{seg} ({', '.join(extra)})" if extra else seg
            # `when` is a relative day ("today"/"yesterday"/"Sat Jun 27") computed
            # on the phone in the user's timezone — so the coach never assumes a
            # backfilled workout happened today.
            when = w.get("when")
            descs.append(f"{when} — {body}" if when else body)
        if descs:
            lines.append("Recent activities (each with the day it happened): "
                         + "; ".join(descs))

        return "\n".join(lines) if lines else None


# Seconds of SILENCE (no user speech, after any reply finishes) before the agent
# goes back to sleep in wake mode. The window resets on every bit of user speech,
# after each reply, and on any "keepalive" the app sends (e.g. while the user is
# browsing the on-screen exercise deck), so it only fires on a genuine long pause.
WAKE_WINDOW_S = 15.0


class WakeController:
    """Hands-free "Hey Coach" gating for workouts.

    Normal Voice tab: never engaged — the agent is always listening (unchanged).

    Workout (wake) mode: the iOS app detects the "Hey Coach" wake word ON-DEVICE
    (Porcupine) and sends a {"type":"wake"} data message. We keep the agent's
    audio INPUT disabled (asleep) so it ignores gym noise/music/grunts, and only
    enable it on wake. After WAKE_WINDOW_S of inactivity we sleep again, so a
    follow-up question doesn't need the wake word. The iOS mic stays published
    the whole time (that's what feeds the on-device wake-word engine); we gate
    purely on the agent's input, not the published track.
    """

    def __init__(self) -> None:
        self.session = None  # set after session.start()
        self.wake_mode = False
        self.awake = False
        self._last_activity = 0.0
        # Set by entrypoint: called with "awake" / "asleep" so the app can play a
        # cue and sync its UI when the coach starts/stops listening.
        self.on_state_change = None

    def bump(self) -> None:
        self._last_activity = time.monotonic()

    def _notify(self, state: str) -> None:
        if self.on_state_change is not None:
            try:
                self.on_state_change(state)
            except Exception as e:
                logger.warning("on_state_change failed: %s", e)

    def enter_wake_mode(self) -> None:
        if self.session is None or self.wake_mode:
            return
        self.wake_mode = True
        self.awake = False
        self.session.interrupt()  # cut any greeting in progress
        self.session.input.set_audio_enabled(False)
        logger.info("😴 wake mode ON — asleep until 'Hey Coach'")

    def exit_wake_mode(self) -> None:
        if self.session is None or not self.wake_mode:
            return
        self.wake_mode = False
        self.awake = True
        self.session.input.set_audio_enabled(True)
        logger.info("🎙️  wake mode OFF — input always on")

    def wake(self) -> None:
        if self.session is None or not self.wake_mode or self.awake:
            return
        self.awake = True
        self.bump()
        self.session.interrupt()
        self.session.input.set_audio_enabled(True)
        logger.info("👋 woke on 'Hey Coach' — listening")
        self._notify("awake")

    def _sleep(self) -> None:
        self.awake = False
        if self.session is not None:
            self.session.input.set_audio_enabled(False)
        logger.info("😴 back to sleep after %.0fs idle", WAKE_WINDOW_S)
        self._notify("asleep")

    async def run_watchdog(self) -> None:
        """Re-sleep after WAKE_WINDOW_S with no USER activity.

        The idle window is measured from the last time the USER did something —
        woke the coach or actually spoke — NOT from the agent's own speech.
        (Bug fix: previously the agent talking reset the timer, so if the model
        replied to background noise or its own echo it kept itself awake
        indefinitely.) When the window elapses we wait for any in-progress reply
        to finish, then sleep — without resetting the timer.
        """
        while True:
            await asyncio.sleep(0.5)
            if self.session is None or not self.wake_mode or not self.awake:
                continue
            if time.monotonic() - self._last_activity <= WAKE_WINDOW_S:
                continue  # the user was active recently — stay awake
            # Window elapsed. Never sleep mid-turn — wait until neither the user
            # nor the agent is speaking, THEN sleep. (No bump() here.)
            if getattr(self.session, "agent_state", None) == "speaking" or \
               getattr(self.session, "user_state", None) == "speaking":
                continue
            self._sleep()


class CoachAgent(Agent):
    def __init__(self, hr: HRContext, whoop: WhoopContext, publish_exercises) -> None:
        super().__init__(instructions=INSTRUCTIONS)
        self._hr = hr
        self._whoop = whoop
        self._publish_exercises = publish_exercises

    @function_tool
    async def show_exercises(self, context: RunContext, muscle: str) -> str:
        """Put a swipeable on-screen deck of exercise demos (animated images) on
        the user's Voice tab. Call this WHENEVER the user asks to see, show, or
        list exercises for a body part — e.g. "show me shoulder exercises",
        "what are some leg exercises", "give me back exercises". `muscle` is the
        body part: shoulders, chest, back, biceps, triceps, abs, legs/quads,
        hamstrings, glutes, calves, forearms, traps."""
        items = exercises_for_muscle(muscle)
        if not items:
            return f"I don't have exercises for '{muscle}'."
        await self._publish_exercises(muscle, items)
        names = ", ".join(e["name"] for e in items[:3])
        logger.info("💪 showing %d %s exercises", len(items), muscle)
        return (f"Done — I've put {len(items)} {muscle} exercises on your screen "
                f"to swipe through, like {names}. Tell the user to swipe through "
                f"them and tap the X when done.")

    @function_tool
    async def get_current_heart_rate(self, context: RunContext) -> str:
        """Get the user's current live heart rate in BPM from their Whoop strap.
        Use this whenever the user asks about their heart rate or how hard they
        are working, or when heart rate is relevant to coaching."""
        snap = self._hr.snapshot()
        if snap is None:
            return ("No live heart rate right now — the workout heart-rate stream "
                    "isn't connected. Ask the user to start a workout.")
        bpm, worn = snap
        if not worn:
            return f"About {bpm} bpm, though the strap may not be in full contact."
        return f"{bpm} bpm."

    @function_tool
    async def get_whoop_status(self, context: RunContext) -> str:
        """Get the user's full Whoop picture for today — recovery, sleep, day
        strain, resting HR, HRV, AND the list of activities/workouts they've
        already logged today (e.g. a walk or run, with duration, strain, HR,
        distance). Use it for readiness/recovery questions AND whenever the user
        asks what they've done today or references a recent activity."""
        s = self._whoop.summary()
        return s or "No Whoop data has come through for this session yet."


async def entrypoint(ctx: agents.JobContext):
    await ctx.connect()

    # Live workout context streamed from the iOS app over the data channel.
    # The agent reads it on demand via the get_current_heart_rate tool; later the
    # dad's-rules engine will read it each tick for proactive HR cues.
    hr = HRContext()
    whoop = WhoopContext()
    wake = WakeController()

    tracer = SessionTracer(
        session_id=getattr(ctx.job, "id", None) or ctx.room.name,
        user_id="ishwar",  # single-user for now; becomes per-user with accounts
        metadata={"room": ctx.room.name},
    )

    def context_snapshot() -> dict:
        """The workout state at the moment of a turn/decision — what the evals
        need to judge whether the coach's output was right for the situation."""
        snap = hr.snapshot()
        return {
            "hr_bpm": snap[0] if snap else None,
            "whoop": whoop.summary(),
            "wake_mode": wake.wake_mode,
            "awake": wake.awake,
        }

    @ctx.room.on("data_received")
    def _on_data(packet: rtc.DataPacket):
        try:
            msg = json.loads(bytes(packet.data).decode("utf-8"))
        except Exception:
            return
        kind = msg.get("type")
        if kind == "hr":
            hr.update(msg.get("bpm"), msg.get("worn"))
            logger.info("❤️  HR %s bpm  worn=%s", msg.get("bpm"), msg.get("worn"))
        elif kind == "whoop_context":
            whoop.update(msg)
            logger.info("🟢 Whoop context: %s", whoop.summary())
        elif kind == "wake_mode":
            # iOS enables this when a workout starts (hands-free "Hey Coach").
            if msg.get("enabled"):
                wake.enter_wake_mode()
            else:
                wake.exit_wake_mode()
        elif kind == "wake":
            # On-device wake word fired on the phone.
            wake.wake()
        elif kind == "keepalive":
            # App keeps the coach awake during silent-but-engaged moments (e.g.
            # browsing the on-screen exercise deck) so it doesn't time out.
            wake.bump()

    def _emit_coach_state(state: str) -> None:
        asyncio.create_task(publish_coach_state(state))

    async def publish_coach_state(state: str) -> None:
        """Tell the app when the coach starts/stops listening (topic
        'coach_state') so it can play a cue and update the UI."""
        try:
            await ctx.room.local_participant.publish_data(
                json.dumps({"type": "coach_state", "state": state}).encode("utf-8"),
                reliable=True, topic="coach_state")
        except Exception as e:
            logger.warning("failed to publish coach_state: %s", e)

    wake.on_state_change = _emit_coach_state

    async def publish_moment(payload: dict) -> None:
        """Send a logged workout moment back to the iOS app (topic 'moment').
        Only while a workout is active, so normal Voice-tab chat isn't logged."""
        if not wake.wake_mode:
            return
        body = {**payload, "type": "moment", "ts": time.time()}
        try:
            await ctx.room.local_participant.publish_data(
                json.dumps(body).encode("utf-8"), reliable=True, topic="moment")
        except Exception as e:
            logger.warning("failed to publish moment: %s", e)

    async def publish_exercises(muscle: str, items: list) -> None:
        """Send an exercise deck to the iOS app (topic 'exercises') to render a
        swipeable on-screen card view of animated demos."""
        body = {
            "type": "exercises",
            "muscle": muscle,
            "items": [
                {"name": e.get("name"), "equipment": e.get("equipment"),
                 "level": e.get("level"), "images": e.get("images", [])}
                for e in items
            ],
        }
        try:
            await ctx.room.local_participant.publish_data(
                json.dumps(body).encode("utf-8"), reliable=True, topic="exercises")
        except Exception as e:
            logger.warning("failed to publish exercises: %s", e)

    session = AgentSession(
        llm=openai.realtime.RealtimeModel(
            voice="alloy",
            # OpenAI's built-in noise reduction, tuned for close mics (AirPods).
            input_audio_noise_reduction="near_field",
            # Transcribe the user's speech so we can deterministically log a
            # workout "moment" per utterance (see _on_user_transcribed). NOTE:
            # gpt-4o-transcribe silently suppressed response generation (the
            # model heard + transcribed but never replied). whisper-1 plus an
            # EXPLICIT create_response keeps responses AND transcription working.
            input_audio_transcription=AudioTranscription(model="whisper-1"),
            # Semantic turn detection, low eagerness. create_response must be
            # explicit so the model still auto-replies after each turn once input
            # transcription is enabled.
            turn_detection=TurnDetection(
                type="semantic_vad", eagerness="low",
                create_response=True, interrupt_response=True),
        ),
        # Require ~0.6s of sustained speech before an interruption counts — a
        # brief echo blip or breath won't cut the agent off.
        min_interruption_duration=0.6,
        # If an interruption turns out to be false (no real user speech follows),
        # resume the reply instead of restarting it — so even a blip that slips
        # through doesn't make the agent "start over".
        resume_false_interruption=True,
        false_interruption_timeout=1.0,
    )

    await session.start(
        agent=CoachAgent(hr, whoop, publish_exercises),
        room=ctx.room,
        room_input_options=RoomInputOptions(
            # Background VOICE cancellation (Krisp): strips other people's voices
            # at a café before the model ever hears them. The main noise fix.
            noise_cancellation=noise_cancellation.BVC(),
        ),
    )

    # Wire up "Hey Coach" gating. Keep the inactivity window fresh whenever a
    # turn is in progress so the watchdog only sleeps after real silence.
    wake.session = session
    oai = AsyncOpenAI()  # for the speaking/breathing analysis (reads OPENAI_API_KEY)

    async def analyze_speaking(transcript: str, bpm) -> str:
        """Expert read of exertion/breathing inferred from WHAT the user said
        (length, fragmentation) + their heart rate. Text-based, so it's reliable
        every time (the speech model calling a tool was not)."""
        hr_str = f"{bpm} bpm" if bpm else "unknown heart rate"
        try:
            resp = await oai.chat.completions.create(
                model="gpt-4o-mini",
                messages=[
                    {"role": "system", "content":
                        "You are an exercise physiologist analysing someone mid-workout. "
                        "From what they just said (its length, fragmentation, whether they "
                        "could complete a sentence) and their heart rate, give a 1–2 sentence "
                        "clinical read of their breathing and exertion. Be specific."},
                    {"role": "user", "content": f"Heart rate: {hr_str}. They said: \"{transcript}\""},
                ],
                max_tokens=90,
            )
            return (resp.choices[0].message.content or "").strip()
        except Exception as e:
            logger.warning("analysis failed: %s", e)
            return f"Said at {hr_str}."

    async def capture_moment(transcript: str) -> None:
        snap = hr.snapshot()
        bpm = snap[0] if snap else None
        analysis = await analyze_speaking(transcript, bpm)
        payload = {"transcript": transcript, "analysis": analysis, "bpm": bpm}
        await publish_moment(payload)
        tracer.moment(payload, context_snapshot())
        logger.info("📝 moment | %s bpm | %s", bpm, transcript[:60])

    # Every transcribed user utterance during a workout (a) keeps the coach awake
    # and (b) gets logged as a moment — deterministic, no reliance on the model.
    @session.on("user_input_transcribed")
    def _on_user_transcribed(ev):
        wake.bump()
        if getattr(ev, "is_final", False) and wake.wake_mode and wake.awake:
            text = (getattr(ev, "transcript", "") or "").strip()
            if text:
                asyncio.create_task(capture_moment(text))

    @session.on("user_state_changed")
    def _on_user_state(ev):
        if getattr(ev, "new_state", None) == "speaking":
            wake.bump()

    # After the agent finishes a reply (returns to "listening"), give the user a
    # fresh follow-up window — so the timer counts silence AFTER the answer, not
    # from when they last spoke before it.
    @session.on("agent_state_changed")
    def _on_agent_state(ev):
        if getattr(ev, "new_state", None) == "listening":
            wake.bump()

    # --- Langfuse tracing: pair each user turn with the coach's reply -----------
    @session.on("conversation_item_added")
    def _on_item(ev):
        item = getattr(ev, "item", None)
        role = getattr(item, "role", None)
        text = getattr(item, "text_content", None) if item else None
        if not text:
            return
        if role == "user":
            tracer.user_said(text, context_snapshot())
        elif role == "assistant":
            tracer.coach_said(text)

    @session.on("function_tools_executed")
    def _on_tools(ev):
        for call in getattr(ev, "function_calls", []) or []:
            tracer.decision(getattr(call, "name", "tool"),
                            {"arguments": getattr(call, "arguments", None)},
                            context_snapshot())

    watchdog_task = asyncio.create_task(wake.run_watchdog())

    async def _cancel_watchdog():
        watchdog_task.cancel()
        tracer.flush()

    ctx.add_shutdown_callback(_cancel_watchdog)

    # Greet first so the user immediately hears the to-and-fro working. In
    # workout/wake mode the iOS app sends {"type":"wake_mode"} right after this,
    # which interrupts the greeting and drops the agent to sleep until "Hey
    # Coach". In the normal Voice tab no wake_mode arrives and behavior is
    # unchanged (always listening).
    await session.generate_reply(
        instructions="In English, greet the user warmly in one short sentence "
        "and ask how they're feeling today."
    )


if __name__ == "__main__":
    agents.cli.run_app(agents.WorkerOptions(entrypoint_fnc=entrypoint))
