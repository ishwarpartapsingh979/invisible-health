# Voice tab — LiveKit + OpenAI Realtime

Live, interruptible voice conversation for the iOS **Voice** tab.

```
iPhone (LiveKit Swift SDK, WebRTC)
   │  GET /token  (public HTTPS)
   ▼
voice-token-server  (Cloud Run, deployed via CI)
   │  returns LiveKit serverUrl + join token
   ▼
LiveKit Cloud room  ◄──  voice_agent.py (worker, runs locally for now)
                              │
                              ▼
                    OpenAI Realtime API (speech ↔ speech)
```

Two pieces, deliberately split:

- **`../voice-token-server/`** — tiny FastAPI service that mints LiveKit join
  tokens. **Public HTTPS on Cloud Run, deployed automatically by CI**
  (`.github/workflows/deploy.yml` → `deploy_token_server`). The phone reaches it
  over normal internet on any network — no Mac / local-network dependency.
  Only needs `livekit-api` + `fastapi` (no conflicts).
- **`voice_agent.py`** — LiveKit Agents worker running OpenAI Realtime. A
  long-running process; **currently run locally** (`python voice_agent.py dev`).
  It connects *outbound* to LiveKit Cloud, so it works from anywhere with
  internet. Deps in `requirements-voice.txt` (kept out of `requirements.txt` so
  they don't break the `run-agent` Cloud Function — see note in that file).

> The iOS side compiles **without** the LiveKit SDK. Until it's added in Xcode,
> the Voice tab shows a setup hint.

---

## 1. LiveKit Cloud project

Create a project at https://cloud.livekit.io → Settings ▸ Keys → copy the
**WebSocket URL** (`wss://<project>.livekit.cloud`), **API Key**, **API Secret**.

## 2. Secrets

- **CI / token server:** add as GitHub repo secrets (Settings ▸ Secrets and
  variables ▸ Actions): `LIVEKIT_URL`, `LIVEKIT_API_KEY`, `LIVEKIT_API_SECRET`.
  The `deploy_token_server` job injects them into Cloud Run.
- **Local agent:** add to `backend/.env` (gitignored): `LIVEKIT_URL`,
  `LIVEKIT_API_KEY`, `LIVEKIT_API_SECRET`, `OPENAI_API_KEY`.

## 3. Token server (Cloud Run, via CI)

Just push — the `deploy_token_server` job builds `voice-token-server/` and
deploys it. The app points at the resulting URL in
`Invisible_Health/Voice/VoiceConfig.swift → tokenServerBaseURL`.

Run it locally instead (optional):
```bash
cd voice-token-server
pip install -r requirements.txt
uvicorn main:app --host 0.0.0.0 --port 8788
```

## 4. Agent (local)

```bash
cd backend
python -m venv venv-voice && source venv-voice/bin/activate
pip install -r requirements-voice.txt
python voice_agent.py dev
```
Uses LiveKit **automatic dispatch** — auto-joins any room in your project,
including `invisible-voice` that the app joins.

> For true mobility (talk during a workout without your Mac on), the agent
> should also be hosted — a follow-up. For now it runs on the Mac.

## 5. iOS app

1. **Add the SDK:** Xcode ▸ File ▸ Add Package Dependencies… →
   `https://github.com/livekit/client-sdk-swift` → add **LiveKit** to the target.
2. `VoiceConfig.tokenServerBaseURL` is set to the Cloud Run HTTPS URL — works on
   Simulator and device with no ATS/local-network changes.
3. Build, open **VOICE**, tap the orb. The agent greets you; talk back.

## Troubleshooting

- **"Couldn't reach the token server"** — confirm the Cloud Run service is
  deployed and `tokenServerBaseURL` matches its URL (`gcloud run services
  describe voice-token-server --region us-central1 --format='value(status.url)'`).
- **Connects but silence** — is `voice_agent.py dev` running, same LiveKit
  project? Check the worker logs for the room join.
- **Cloud Run deploy fails on permissions** — the deploy service account needs
  `roles/run.admin`, `roles/iam.serviceAccountUser`, and Cloud Build perms.
