"""
Voice token server — public HTTPS endpoint (Cloud Run).

The iOS app calls GET /token?room=...&identity=... and gets back the LiveKit
server URL plus a short-lived join token. The LiveKit API secret stays
server-side. Deployed to Cloud Run via CI (.github/workflows/deploy.yml), so the
phone reaches it over normal internet on any network — no Mac / local-network
dependency.

Only needs livekit-api + fastapi + uvicorn (NOT livekit-agents), so it shares
none of the agent's dependency conflicts.
"""

import os

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from livekit import api

LIVEKIT_URL = os.environ["LIVEKIT_URL"]
LIVEKIT_API_KEY = os.environ["LIVEKIT_API_KEY"]
LIVEKIT_API_SECRET = os.environ["LIVEKIT_API_SECRET"]

app = FastAPI(title="Invisible Health — voice token server")

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
