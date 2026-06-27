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

from dotenv import load_dotenv

from livekit import agents
from livekit.agents import Agent, AgentSession, RoomInputOptions
from livekit.plugins import noise_cancellation, openai
from openai.types.beta.realtime.session import TurnDetection

load_dotenv()

INSTRUCTIONS = """
You are the Invisible Health voice coach. You speak with the user about their
health, recovery, sleep, training, and nutrition.

LANGUAGE: Always speak in English (US). Even if you hear background chatter,
other languages, or muffled/partial words, respond only in English — never
switch languages unless the user clearly and explicitly asks you to.

Style:
- Warm, calm, and concise. Sound like a thoughtful human coach, not a chatbot.
- Keep replies short for a back-and-forth conversation — usually 1–3 sentences.
- Ask one question at a time. Leave room for the user to interrupt.
- Be encouraging and specific. Avoid medical diagnosis; suggest seeing a
  professional for anything clinical.
"""


class CoachAgent(Agent):
    def __init__(self) -> None:
        super().__init__(instructions=INSTRUCTIONS)


async def entrypoint(ctx: agents.JobContext):
    await ctx.connect()

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
        agent=CoachAgent(),
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
