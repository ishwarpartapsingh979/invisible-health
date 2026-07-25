import Foundation
import SwiftUI
#if canImport(MusicKit)
import MusicKit
#endif

/// Which music service the user linked at onboarding. Music is part of the
/// immersive workout experience (coach voice + world soundscape + MUSIC over
/// AirPods), so the experience layer drives it in-session.
enum MusicService: String, CaseIterable, Identifiable {
    case appleMusic = "apple_music"
    case spotify = "spotify"
    case none = ""

    var id: String { rawValue }
    var label: String {
        switch self {
        case .appleMusic: return "Apple Music"
        case .spotify: return "Spotify"
        case .none: return "No music service"
        }
    }
}

/// Owns the user's music-service connection.
///
/// Scope TODAY: capture the CHOICE at onboarding + request Apple Music
/// authorization via MusicKit. In-session playback control is a later step
/// (open design call: control playback in-app vs. hand off to the music app).
///
/// - **Apple Music** is self-contained (MusicKit, no external account). It needs
///   the **MusicKit capability** + an **`NSAppleMusicUsageDescription`** set in
///   Xcode (the app has no checked-in Info.plist — those are in build settings),
///   or `MusicAuthorization.request()` traps at runtime.
/// - **Spotify** needs a registered developer app (client id + redirect URI) and
///   the Spotify iOS SDK before it can truly connect. Until that's wired,
///   choosing Spotify only RECORDS the preference (the coach still learns it).
@MainActor
final class MusicConnectionManager: ObservableObject {
    static let shared = MusicConnectionManager()

    /// The linked service (persisted; streamed to the coach via the profile).
    @Published private(set) var service: MusicService
    /// True once Apple Music authorization has been granted this session.
    @Published private(set) var appleMusicAuthorized = false

    private let key = "music.service"

    private init() {
        let raw = UserDefaults.standard.string(forKey: key) ?? ""
        service = MusicService(rawValue: raw) ?? .none
    }

    private func setService(_ s: MusicService) {
        service = s
        UserDefaults.standard.set(s.rawValue, forKey: key)
    }

    /// Connect Apple Music: request MusicKit authorization. Returns whether it
    /// ended up authorized. Records the choice on success.
    @discardableResult
    func connectAppleMusic() async -> Bool {
        #if canImport(MusicKit)
        if #available(iOS 15.0, *) {
            let status = await MusicAuthorization.request()
            let ok = (status == .authorized)
            appleMusicAuthorized = ok
            if ok { setService(.appleMusic) }
            return ok
        }
        #endif
        return false
    }

    /// Spotify: not wired yet (needs the developer app + SDK). Records the
    /// preference so the coach knows; the real connect comes later.
    func chooseSpotify() {
        setService(.spotify)
    }

    /// Clear the linked service.
    func disconnect() {
        setService(.none)
        appleMusicAuthorized = false
    }
}

/// Onboarding step: link a music service so the experience can play music in
/// your workouts. OAuth/permission is inherently tappable (not voice), so this
/// is a small tap-through inside the setup form.
struct MusicConnectView: View {
    @ObservedObject private var music = MusicConnectionManager.shared
    /// Fires whenever the choice changes, so the parent persists it on the
    /// profile (which streams `music_service` to the coach).
    var onChange: (MusicService) -> Void = { _ in }
    @State private var connecting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your music powers the experience — coach, soundscape and your tracks over your AirPods.")
                .font(.footnote).foregroundColor(.secondary)

            Button {
                connecting = true
                Task {
                    await music.connectAppleMusic()
                    connecting = false
                    onChange(music.service)
                }
            } label: {
                connectRow("Apple Music",
                           connected: music.service == .appleMusic && music.appleMusicAuthorized,
                           busy: connecting)
            }
            .disabled(connecting)

            Button {
                music.chooseSpotify()
                onChange(music.service)
            } label: {
                connectRow("Spotify (coming soon)", connected: music.service == .spotify, busy: false)
            }
        }
    }

    private func connectRow(_ name: String, connected: Bool, busy: Bool) -> some View {
        HStack {
            Image(systemName: "music.note")
            Text(name)
            Spacer()
            if busy {
                ProgressView()
            } else {
                Text(connected ? "Connected" : "Connect")
                    .foregroundColor(connected ? .green : .blue)
            }
        }
        .font(.subheadline)
    }
}
