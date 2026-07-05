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
final class VoiceCallManager: ObservableObject, RoomDelegate {

    /// True when the LiveKit SDK is linked.
    static let isAvailable = true

    @Published private(set) var state: VoiceCallState = .idle
    @Published private(set) var isMicEnabled = true

    /// Called when the agent publishes a logged workout "moment" (transcript +
    /// breathing analysis + HR) back over the data channel during a workout.
    var onMoment: ((_ transcript: String, _ analysis: String, _ bpm: Int?) -> Void)?

    /// Called when the agent sends an exercise deck (user asked to see exercises
    /// for a muscle group) — drives the on-screen swipeable card overlay.
    var onExercises: ((_ muscle: String, _ items: [ExerciseItem]) -> Void)?

    /// Called when the coach starts ("awake") or stops ("asleep") listening, so
    /// the UI can play a cue and sync state.
    var onCoachState: ((_ state: String) -> Void)?

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
        configureAudioSessionForMusic()
        do {
            let creds = try await VoiceTokenService.fetch()
            room.add(delegate: self)   // receive "moment" data from the agent
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

    /// Publish the latest Whoop snapshot to the agent once at workout start
    /// (reliable delivery, topic "whoop").
    func sendWhoopContext(_ payload: [String: Any]) async {
        guard state == .connected else { return }
        var p = payload
        p["type"] = "whoop_context"
        guard let data = try? JSONSerialization.data(withJSONObject: p) else { return }
        try? await room.localParticipant.publish(
            data: data,
            options: DataPublishOptions(topic: "whoop", reliable: true)
        )
    }

    // MARK: - "Hey Coach" wake word

    private var wakeDetector: WakeWordDetector?

    /// Start on-device "Hey Coach" detection by tapping LiveKit's captured mic.
    /// Returns true if the wake word is configured and now armed; false if it
    /// isn't set up (caller should then stay in always-on listening).
    func enableWakeWord(onWake: @escaping () -> Void) -> Bool {
        #if canImport(LiveKitWakeWord)
        guard let detector = WakeWordDetector(onWake: onWake) else { return false }
        wakeDetector = detector
        // Tap the single mic LiveKit already owns — no separate audio input.
        AudioManager.shared.capturePostProcessingDelegate = detector
        return true
        #else
        return false
        #endif
    }

    /// Stop wake-word detection and release the mic tap.
    func disableWakeWord() {
        #if canImport(LiveKitWakeWord)
        if AudioManager.shared.capturePostProcessingDelegate === wakeDetector {
            AudioManager.shared.capturePostProcessingDelegate = nil
        }
        wakeDetector?.stop()
        wakeDetector = nil
        #endif
    }

    // MARK: - Audio ducking (play nicely with the user's music)

    /// Configure the LiveKit audio session so the user's music keeps playing
    /// (mixWithOthers) but CAN be ducked (duckOthers). We then control the
    /// amount at runtime via `duckingLevel`: `.min` ≈ music near-full while idle,
    /// `.max` while the coach is talking. Set before connecting.
    private func configureAudioSessionForMusic() {
        let base = AudioSessionConfiguration.playAndRecordSpeaker
        AudioManager.shared.sessionConfiguration = AudioSessionConfiguration(
            category: base.category,
            categoryOptions: base.categoryOptions.union(.duckOthers),
            mode: base.mode)
        AudioManager.shared.duckingLevel = .min   // music as loud as possible when idle
    }

    /// Duck the user's music while the coach is conversing; restore when idle.
    func setMusicDucking(_ ducking: Bool) {
        AudioManager.shared.duckingLevel = ducking ? .max : .min
    }

    /// Tell the agent to enter (or leave) hands-free wake mode — it sleeps
    /// (ignores audio) until a `wake` message, re-sleeping after a short window.
    func sendWakeMode(_ enabled: Bool) async {
        await sendControl(["type": "wake_mode", "enabled": enabled], topic: "mode")
    }

    /// Tell the agent the wake word just fired — open its ears for a turn.
    func sendWake() async {
        await sendControl(["type": "wake"], topic: "wake")
    }

    /// Keep the coach awake during a silent-but-engaged moment (e.g. while the
    /// exercise deck is open) so its idle timer doesn't sleep it.
    func sendKeepAlive() async {
        await sendControl(["type": "keepalive"], topic: "keepalive")
    }

    private func sendControl(_ payload: [String: Any], topic: String) async {
        guard state == .connected,
              let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        try? await room.localParticipant.publish(
            data: data,
            options: DataPublishOptions(topic: topic, reliable: true)
        )
    }

    // MARK: - RoomDelegate (incoming data from the agent)

    /// The agent publishes a "moment" packet each time the user speaks during a
    /// workout. Called off the main actor by the SDK, so we hop back to forward it.
    nonisolated func room(_ room: Room, participant: RemoteParticipant?,
                          didReceiveData data: Data, forTopic topic: String,
                          encryptionType: EncryptionType) {
        switch topic {
        case "moment":
            guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let transcript = obj["transcript"] as? String,
                  let analysis = obj["analysis"] as? String else { return }
            let bpm = obj["bpm"] as? Int
            Task { @MainActor in self.onMoment?(transcript, analysis, bpm) }
        case "exercises":
            struct Payload: Decodable { let muscle: String?; let items: [ExerciseItem] }
            guard let p = try? JSONDecoder().decode(Payload.self, from: data) else { return }
            let muscle = p.muscle ?? "Exercises"
            Task { @MainActor in self.onExercises?(muscle, p.items) }
        case "coach_state":
            guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let state = obj["state"] as? String else { return }
            Task { @MainActor in
                self.setMusicDucking(state == "awake")   // duck music while talking
                self.onCoachState?(state)
            }
        default:
            return
        }
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
    var onMoment: ((_ transcript: String, _ analysis: String, _ bpm: Int?) -> Void)?
    var onExercises: ((_ muscle: String, _ items: [ExerciseItem]) -> Void)?
    var onCoachState: ((_ state: String) -> Void)?
    func sendKeepAlive() async {}

    func start() async {
        state = .failed("Add the LiveKit Swift SDK package in Xcode to enable Voice.")
    }
    func stop() async {}
    func toggleMic() async {}
    func sendHeartRate(_ sample: HeartRateSample) async {}
    func sendWhoopContext(_ payload: [String: Any]) async {}
    func enableWakeWord(onWake: @escaping () -> Void) -> Bool { false }
    func disableWakeWord() {}
    func sendWakeMode(_ enabled: Bool) async {}
    func sendWake() async {}
}

#endif
