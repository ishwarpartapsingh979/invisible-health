import Foundation
import Combine

/// Drives a live, interruptible voice conversation over LiveKit (WebRTC).
///
/// The whole LiveKit-dependent implementation is guarded by `#if canImport(LiveKit)`
/// so the app keeps compiling BEFORE the LiveKit Swift SDK package is added in
/// Xcode. Until then, a stub with the same public surface is used and the Voice
/// tab shows a setup hint instead of crashing the build.
///
/// To enable the real path: in Xcode →
///   File ▸ Add Package Dependencies… ▸ https://github.com/livekit/client-sdk-swift
///   (add the `LiveKit` product to the Invisible_Health target).

enum VoiceCallState: Equatable {
    case idle
    case connecting
    case connected
    case failed(String)
}

#if canImport(LiveKit)
import LiveKit

@MainActor
final class VoiceCallManager: ObservableObject {

    /// True when the LiveKit SDK is linked.
    static let isAvailable = true

    @Published private(set) var state: VoiceCallState = .idle
    @Published private(set) var isMicEnabled = true

    /// The underlying LiveKit room. Exposed so SwiftUI can observe participant
    /// audio activity (it conforms to ObservableObject in the SDK).
    let room = Room()

    /// Connect to the room, publish the mic, and let the agent greet the user.
    func start() async {
        guard VoiceConfig.isConfigured else {
            state = .failed("Set your token server URL in VoiceConfig.swift")
            return
        }

        state = .connecting
        do {
            let creds = try await VoiceTokenService.fetch()
            try await room.connect(url: creds.serverUrl, token: creds.token)
            // Publish the microphone. The LiveKit SDK owns AVAudioSession,
            // playback routing, and interruption handling from here on.
            try await room.localParticipant.setMicrophone(enabled: true)
            isMicEnabled = true
            state = .connected
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Leave the room and tear the call down.
    func stop() async {
        await room.disconnect()
        isMicEnabled = false
        state = .idle
    }

    /// Mute / unmute the local microphone without leaving the room.
    func toggleMic() async {
        let target = !isMicEnabled
        do {
            try await room.localParticipant.setMicrophone(enabled: target)
            isMicEnabled = target
        } catch {
            // Keep the previous mic state if the toggle failed.
        }
    }

    /// Publish one heart-rate sample to the agent over the room's data channel.
    /// Lossy (latest-wins) on topic "hr" — for periodic HR the newest value
    /// matters more than guaranteed delivery, and it's lower latency.
    func sendHeartRate(_ sample: HeartRateSample) async {
        guard state == .connected else { return }
        let payload: [String: Any] = [
            "type": "hr",
            "bpm": sample.bpm,
            "worn": sample.worn,
            "ts": sample.timestamp.timeIntervalSince1970,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        try? await room.localParticipant.publish(
            data: data,
            options: DataPublishOptions(topic: "hr", reliable: false)
        )
    }
}

#else

// MARK: - Stub used until the LiveKit Swift SDK package is added.

@MainActor
final class VoiceCallManager: ObservableObject {

    static let isAvailable = false

    @Published private(set) var state: VoiceCallState =
        .failed("Add the LiveKit Swift SDK package in Xcode to enable Voice.")
    @Published private(set) var isMicEnabled = false

    func start() async {
        state = .failed("Add the LiveKit Swift SDK package in Xcode to enable Voice.")
    }
    func stop() async {}
    func toggleMic() async {}
    func sendHeartRate(_ sample: HeartRateSample) async {}
}

#endif
