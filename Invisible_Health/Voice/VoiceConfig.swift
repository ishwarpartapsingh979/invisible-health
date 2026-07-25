import Foundation

/// Configuration + token fetching for the Voice tab.
///
/// The Voice tab connects to a LiveKit Cloud room over WebRTC. A small Python
/// agent (see `backend/voice_agent.py`) joins the same room and bridges audio to
/// the OpenAI Realtime API (speech-to-speech). The iOS app never sees the
/// LiveKit API secret or the OpenAI key — it only fetches a short-lived join
/// token from the local token server (see `backend/voice_token_server.py`).
enum VoiceConfig {

    /// Base URL of the token server that mints LiveKit access tokens.
    ///
    /// Public HTTPS endpoint on Cloud Run, deployed via CI
    /// (.github/workflows/deploy.yml → `voice-token-server`). The phone reaches
    /// this over normal internet on any network — no Mac / local-network
    /// dependency, no ATS exception needed.
    ///
    /// Live Cloud Run URL (verified working). If you redeploy under a new
    /// service name/region, update this — get it via:
    ///   gcloud run services describe voice-token-server \
    ///     --region us-central1 --format='value(status.url)'
    static let tokenServerBaseURL = "https://voice-token-server-zupjde2jpq-uc.a.run.app"

    /// The room the iOS client and the Python agent both join.
    static let roomName = "invisible-voice"

    /// Dev/continuity override for the per-user id. When set, it wins over Sign
    /// in with Apple and skips the sign-in gate — the whole app runs as this user.
    ///
    /// Leave `nil` for the normal multi-user path (each person signs in with
    /// Apple; see `AuthManager`). Ishwar: set this to `"ishwar"` on your build to
    /// keep your existing Supabase history and skip the gate. (A shared TestFlight
    /// build must ship with this `nil` so Uday/Jasmine get their own ids.)
    static let devUserIdOverride: String? = nil

    /// The current per-user `user_id` for all data reads/writes (token identity +
    /// `?user_id=` on the data tabs). Falls back to `"ishwar"` only if somehow
    /// unresolved, matching the agent's back-compat fallback.
    static var currentUserId: String {
        AuthManager.shared.userId ?? "ishwar"
    }

    /// Identity for this app's participant in the room: `"<user>-ios"`. The agent
    /// strips the `-ios` suffix to recover `currentUserId`.
    static var participantIdentity: String { "\(currentUserId)-ios" }

    /// True once `tokenServerBaseURL` has been pointed somewhere real.
    static var isConfigured: Bool {
        !tokenServerBaseURL.contains("CHANGE-ME")
    }
}

/// On-device "Hey Coach" wake word, using LiveKit's open-source wake-word engine
/// (https://github.com/livekit/livekit-wakeword — Apache 2.0, ONNX, runs fully
/// on-device). No account, no API key.
///
/// SETUP (one-time):
///  1. Add the SPM package: File ▸ Add Package Dependencies… ▸
///     https://github.com/livekit/livekit-wakeword ▸ add the `LiveKitWakeWord`
///     product to the "Invisible_Health" target. (The mel + embedding ONNX
///     models and the ONNX runtime ship inside the package.)
///  2. Provide the classifier model `hey_coach.onnx` and drag it into the Xcode
///     project (target membership "Invisible_Health"). Train it in one command:
///        pip install "livekit-wakeword[train,eval,export]"
///        livekit-wakeword run hey_coach.yaml   # synthetic TTS data → ONNX
///     (or drop in LiveKit's pretrained `hey_livekit.onnx` to validate the flow
///     first and just say "Hey LiveKit" — set `modelResource` accordingly.)
/// Until the model is bundled, workouts fall back to always-on listening (no
/// wake word) — the app still builds and runs.
enum WakeWordConfig {

    /// Resource name of the bundled classifier: `<modelResource>.onnx`.
    /// Custom "Hey Coach" model (trained 2026-06-28). `hey_livekit.onnx` is also
    /// bundled as a fallback — switch this back to "hey_livekit" to A/B.
    static let modelResource = "hey_coach"

    /// Detection score (0…1) at or above which the wake word fires. This
    /// Mac-trained model has poor separation: at 0.7 it fired on NOTHING (missed
    /// "Hey Coach" entirely), at 0.5 it fires reliably but also on partials like
    /// "hey". 0.5 is the known-working value — prioritising "it actually wakes"
    /// over the occasional stray trigger. The real fix is a better model
    /// (LiveKit's pretrained "hey_livekit", or retrain "hey_coach" on a GPU with
    /// configs/prod.yaml + full ACAV).
    static let threshold: Float = 0.5

    /// URL of the bundled classifier model, or nil if it isn't in the bundle.
    static var modelURL: URL? {
        Bundle.main.url(forResource: modelResource, withExtension: "onnx")
    }

    /// True once the classifier model is bundled in the app.
    static var isConfigured: Bool { modelURL != nil }
}

/// Fetches a LiveKit server URL + join token from the token server.
struct VoiceTokenService {

    struct Response: Decodable {
        let serverUrl: String
        let token: String
    }

    enum TokenError: LocalizedError {
        case badResponse
        var errorDescription: String? {
            "Couldn't reach the token server. Is backend/voice_token_server.py running?"
        }
    }

    static func fetch(room: String = VoiceConfig.roomName) async throws -> Response {
        var comps = URLComponents(string: VoiceConfig.tokenServerBaseURL + "/token")!
        comps.queryItems = [
            URLQueryItem(name: "room", value: room),
            URLQueryItem(name: "identity", value: VoiceConfig.participantIdentity)
        ]
        let (data, resp) = try await URLSession.shared.data(from: comps.url!)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw TokenError.badResponse
        }
        return try JSONDecoder().decode(Response.self, from: data)
    }
}
