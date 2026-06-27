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

import json
import logging
import time

from dotenv import load_dotenv

from livekit import agents, rtc
from livekit.agents import Agent, AgentSession, RoomInputOptions, RunContext, function_tool
from livekit.plugins import noise_cancellation, openai
from openai.types.beta.realtime.session import TurnDetection

load_dotenv()

logger = logging.getLogger("voice-agent")

INSTRUCTIONS = """
You are the Invisible Health voice coach. You speak with the user about their
health, recovery, sleep, training, and nutrition.

LANGUAGE: Always speak in English (US). Even if you hear background chatter,
other languages, or muffled/partial words, respond only in English — never
switch languages unless the user clearly and explicitly asks you to.

LIVE HEART RATE: When the user is working out, their real-time heart rate is
available via the get_current_heart_rate tool. Call it whenever they ask about
their heart rate or how hard they're working, or when HR is relevant to your
coaching. Never guess the number — always read it from the tool.

Style:
- Warm, calm, and concise. Sound like a thoughtful human coach, not a chatbot.
- Keep replies short for a back-and-forth conversation — usually 1–3 sentences.
- Ask one question at a time. Leave room for the user to interrupt.
- Be encouraging and specific. Avoid medical diagnosis; suggest seeing a
  professional for anything clinical.
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


class CoachAgent(Agent):
    def __init__(self, hr: HRContext) -> None:
        super().__init__(instructions=INSTRUCTIONS)
        self._hr = hr

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


async def entrypoint(ctx: agents.JobContext):
    await ctx.connect()

    # Live workout context streamed from the iOS app over the data channel.
    # The agent reads it on demand via the get_current_heart_rate tool; later the
    # dad's-rules engine will read it each tick for proactive HR cues.
    hr = HRContext()

    @ctx.room.on("data_received")
    def _on_data(packet: rtc.DataPacket):
        try:
            msg = json.loads(bytes(packet.data).decode("utf-8"))
        except Exception:
            return
        if msg.get("type") == "hr":
            hr.update(msg.get("bpm"), msg.get("worn"))
            logger.info("❤️  HR %s bpm  worn=%s", msg.get("bpm"), msg.get("worn"))

    session = AgentSession(
        llm=openai.realtime.RealtimeModel(
            voice="alloy",
            # OpenAI's built-in noise reduction, tuned for close mics (AirPods).
            input_audio_noise_reduction="near_field",
            # Semantic turn detection with LOW eagerness: the model waits for a
            # real end-of-turn instead of jumping on café noise, so it stops
            # interrupting itself mid-answer.
            turn_detection=TurnDetection(type="semantic_vad", eagerness="low"),
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
        agent=CoachAgent(hr),
        room=ctx.room,
        room_input_options=RoomInputOptions(
            # Background VOICE cancellation (Krisp): strips other people's voices
            # at a café before the model ever hears them. The main noise fix.
            noise_cancellation=noise_cancellation.BVC(),
        ),
    )

    # Greet first so the user immediately hears the to-and-fro working.
    await session.generate_reply(
        instructions="In English, greet the user warmly in one short sentence "
        "and ask how they're feeling today."
    )


if __name__ == "__main__":
    agents.cli.run_app(agents.WorkerOptions(entrypoint_fnc=entrypoint))
