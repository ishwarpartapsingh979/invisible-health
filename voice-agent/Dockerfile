# Container for the LiveKit Cloud-hosted voice coach worker (voice_agent.py).
# Runs as a long-lived worker that connects OUTBOUND to LiveKit Cloud and waits
# for jobs — LiveKit auto-dispatches it into the "invisible-voice" room. Durable
# replacement for `python voice_agent.py dev` on the Mac (which dies on network
# blips). Built + deployed by the `deploy_agent` job in deploy.yml.
#
# This directory is self-contained ON PURPOSE: its requirements.txt holds the
# voice-worker deps (livekit-agents, aiohttp 3.10 / openai 2.x), which conflict
# with backend/requirements.txt (the run-agent Cloud Function: aiohttp 3.9 /
# openai 1.x). Keeping them apart is what lets both deploy.
FROM python:3.13-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Pre-download plugin model files (Krisp BVC noise cancellation) BEFORE copying
# source, so this heavy layer stays cached when only the agent code changes.
RUN python -m livekit.agents download-files

# Agent source. guidance.py is imported by voice_agent.py (the dad's-rules seam);
# exercises.json is the bundled exercise library for the on-screen demo deck.
COPY voice_agent.py guidance.py exercises.json rules_engine.py ./
# Pre-rendered hype/motivation clips (Adam voice, ElevenLabs) + manifest, played
# by the agent at workout start and effort moments. No runtime ElevenLabs key.
COPY hype ./hype/

# Worker mode: connect to LiveKit Cloud and wait for jobs (NOT `dev`).
CMD ["python", "voice_agent.py", "start"]
