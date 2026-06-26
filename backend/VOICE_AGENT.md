# Voice tab — LiveKit + OpenAI Realtime

Live, interruptible voice conversation for the iOS **Voice** tab.

```
iPhone (LiveKit Swift SDK, WebRTC)
        │  join token
        ▼
voice_token_server.py  ──►  LiveKit Cloud room  ◄──  voice_agent.py (worker)
                                                          │
                                                          ▼
                                                OpenAI Realtime API (speech↔speech)
```

- **`voice_agent.py`** — LiveKit Agents worker. Joins the room, runs OpenAI
  Realtime speech-to-speech. Long-running process (run it yourself; it is **not**
  the `run-agent` Cloud Function).
- **`voice_token_server.py`** — tiny FastAPI server that mints LiveKit join
  tokens for the app. Keeps the LiveKit secret server-side.
- Deps live in `requirements-voice.txt` (kept out of `requirements.txt` so they
  don't break the `run-agent` Cloud Function deploy — see note in that file).

> The iOS side compiles **without** any of this. Until the LiveKit Swift SDK is
> added in Xcode, the Voice tab just shows a setup hint.

---

## 1. LiveKit Cloud project (free)

1. Create a project at https://cloud.livekit.io
2. Settings ▸ Keys → copy the **WebSocket URL** (`wss://<project>.livekit.cloud`),
   **API Key**, and **API Secret**.

## 2. Env vars

Add to `backend/.env` (gitignored):

```
LIVEKIT_URL=wss://<project>.livekit.cloud
LIVEKIT_API_KEY=API...
LIVEKIT_API_SECRET=...
OPENAI_API_KEY=sk-...        # your Realtime-enabled key
```

## 3. Install + run (from `backend/`)

Use a dedicated venv so LiveKit's native deps don't disturb the other backend tools:

```bash
python -m venv venv-voice
source venv-voice/bin/activate
pip install -r requirements-voice.txt

# terminal A — token server (app fetches tokens here)
uvicorn voice_token_server:app --host 0.0.0.0 --port 8080

# terminal B — the voice agent worker
python voice_agent.py dev
```

The worker uses LiveKit **automatic dispatch**: it auto-joins any room in your
project, including `invisible-voice` that the app joins.

## 4. iOS app

1. **Add the SDK:** Xcode ▸ File ▸ Add Package Dependencies… →
   `https://github.com/livekit/client-sdk-swift` → add the **LiveKit** product to
   the `Invisible_Health` target. (This flips `#if canImport(LiveKit)` on.)
2. **Point at the token server:** `Invisible_Health/Voice/VoiceConfig.swift`
   → `tokenServerBaseURL`:
   - Simulator: `http://localhost:8080`
   - Real iPhone: `http://<your-mac-LAN-IP>:8080` (Mac + phone on same Wi-Fi)
3. Build, open the **VOICE** tab, tap the orb. The agent greets you; talk back.

### Real-device HTTP note (ATS)

Plain `http://` to a LAN IP is blocked by App Transport Security. Options:
- Run the token server behind HTTPS (e.g. your existing nip.io VM), **or**
- Add a temporary ATS exception in the Info.plist build settings for dev.

`localhost` on the Simulator works without changes.

## Troubleshooting

- **App says "Couldn't reach the token server"** — is `uvicorn` running? On a
  real device, is `tokenServerBaseURL` your Mac's LAN IP (not localhost)?
- **Connects but silence** — is `voice_agent.py dev` running and pointed at the
  same LiveKit project? Check the worker logs for the room join.
- **pip conflict on `openai`** — the livekit openai plugin may need a newer
  `openai` than the pinned `==1.59.5`. Bump it and re-test the Whisper path.
