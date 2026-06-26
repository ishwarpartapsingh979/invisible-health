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
from livekit.plugins import openai

load_dotenv()

INSTRUCTIONS = """
You are the Invisible Health voice coach. You speak with the user about their
health, recovery, sleep, training, and nutrition.

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
        # Speech-to-speech. Swap `voice` to taste (alloy, echo, shimmer, ...).
        llm=openai.realtime.RealtimeModel(voice="alloy"),
    )

    await session.start(
        agent=CoachAgent(),
        room=ctx.room,
        room_input_options=RoomInputOptions(),
    )

    # Greet first so the user immediately hears the to-and-fro working.
    await session.generate_reply(
        instructions="Greet the user warmly in one sentence and ask how they're "
        "feeling today."
    )


if __name__ == "__main__":
    agents.cli.run_app(agents.WorkerOptions(entrypoint_fnc=entrypoint))
