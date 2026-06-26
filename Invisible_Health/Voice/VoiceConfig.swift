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

    /// Identity for this app's participant in the room.
    static let participantIdentity = "ishwar-ios"

    /// True once `tokenServerBaseURL` has been pointed somewhere real.
    static var isConfigured: Bool {
        !tokenServerBaseURL.contains("CHANGE-ME")
    }
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

    static func fetch() async throws -> Response {
        var comps = URLComponents(string: VoiceConfig.tokenServerBaseURL + "/token")!
        comps.queryItems = [
            URLQueryItem(name: "room", value: VoiceConfig.roomName),
            URLQueryItem(name: "identity", value: VoiceConfig.participantIdentity)
        ]
        let (data, resp) = try await URLSession.shared.data(from: comps.url!)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw TokenError.badResponse
        }
        return try JSONDecoder().decode(Response.self, from: data)
    }
}
