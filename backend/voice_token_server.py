"""
Minimal LiveKit token server for the iOS Voice tab.

The app calls GET /token?room=...&identity=... and gets back the LiveKit server
URL plus a short-lived join token. The LiveKit API secret never leaves this
process. For local dogfood only — lock this down before shipping.

Run (dev), from backend/:
    source venv-voice/bin/activate    # same venv as voice_agent.py
    uvicorn voice_token_server:app --host 0.0.0.0 --port 8080
"""

import os

from dotenv import load_dotenv
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from livekit import api

load_dotenv()

LIVEKIT_URL = os.environ["LIVEKIT_URL"]
LIVEKIT_API_KEY = os.environ["LIVEKIT_API_KEY"]
LIVEKIT_API_SECRET = os.environ["LIVEKIT_API_SECRET"]

app = FastAPI(title="Invisible Health Voice — token server")

# Wide-open CORS is fine for a local dev token server.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/health")
def health():
    return {"ok": True}


@app.get("/token")
def token(room: str = "invisible-voice", identity: str = "ios-user"):
    grant = api.VideoGrants(room_join=True, room=room, can_publish=True, can_subscribe=True)
    jwt = (
        api.AccessToken(LIVEKIT_API_KEY, LIVEKIT_API_SECRET)
        .with_identity(identity)
        .with_name(identity)
        .with_grants(grant)
        .to_jwt()
    )
    return {"serverUrl": LIVEKIT_URL, "token": jwt}
