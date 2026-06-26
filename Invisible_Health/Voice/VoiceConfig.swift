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
    /// Run `backend/voice_token_server.py`, then point this at your Mac:
    ///   • iOS Simulator : http://localhost:8788
    ///   • Real iPhone   : http://<your-mac-LAN-IP>:8788   (e.g. http://192.168.1.42:8788)
    ///
    /// NOTE: For a real device over plain HTTP you'll hit App Transport Security.
    /// Easiest fixes: run the token server behind HTTPS (e.g. your existing
    /// nip.io VM) or add an ATS exception. See backend/VOICE_AGENT.md.
    /// (Port 8788 chosen because 8080 was already in use locally.)
    static let tokenServerBaseURL = "http://localhost:8788"

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
