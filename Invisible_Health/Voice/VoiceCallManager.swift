import Foundation
import Combine
import CoreLocation

/// One-shot COARSE location for "near me" lookups (restaurants/gyms) — separate
/// from the workout GPS (LocationProvider, which tracks continuously). Fetches a
/// single fix on demand.
final class CoarseLocator: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var completion: ((CLLocation?) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func fetch(_ done: @escaping (CLLocation?) -> Void) {
        completion = done
        manager.requestWhenInUseAuthorization()
        manager.requestLocation()
    }

    func locationManager(_ m: CLLocationManager, didUpdateLocations locs: [CLLocation]) {
        completion?(locs.last); completion = nil
    }
    func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {
        completion?(nil); completion = nil
    }
}

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
    /// True once the agent has actually joined the room and is ready to hear you.
    /// Until then the UI shows "waking your coach" so early speech isn't lost to the
    /// warm-up gap (issue #29).
    @Published private(set) var agentReady = false

    /// Called when the agent publishes a logged workout "moment" (transcript +
    /// breathing analysis + HR) back over the data channel during a workout.
    var onMoment: ((_ transcript: String, _ analysis: String, _ bpm: Int?) -> Void)?

    /// Called when the agent sends an exercise deck (user asked to see exercises
    /// for a muscle group) — drives the on-screen swipeable card overlay.
    var onExercises: ((_ muscle: String, _ items: [ExerciseItem]) -> Void)?

    /// Called when the coach starts ("awake") or stops ("asleep") listening, so
    /// the UI can play a cue and sync state.
    var onCoachState: ((_ state: String) -> Void)?

    /// Called when the coach sends today's 3 plan options — drives the plan cards.
    var onPlans: ((_ plans: [CoachPlan]) -> Void)?

    /// Coach detected an outdoor run → start GPS (with the permission prompt).
    var onStartGPS: (() -> Void)?
    /// Coach finished the opening plan chat → switch to hands-free "Hey Coach".
    var onHandsfree: (() -> Void)?
    /// Coach saved the profile via the voice interview → store it + dismiss onboarding.
    var onProfileSaved: ((_ profile: [String: Any]) -> Void)?
    /// Coach set the chosen-workout label → show it on the workout screen.
    var onWorkoutLabel: ((_ label: String) -> Void)?
    /// Coach pushed the weekly nutrition summary (topic "nutrition_summary").
    var onNutritionSummary: ((_ summary: NutritionSummary) -> Void)?
    /// Coach pushed a results list to show on screen (topic "results") — nearby
    /// places, meal ideas, etc.
    var onResults: ((_ results: AgentResults) -> Void)?

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
        agentReady = false
        configureAudioSessionForMusic()
        do {
            // Unique room per connect so LiveKit dispatches a FRESH agent every
            // time — reopening the app no longer lands on a stale/asleep agent in
            // the same room and going silent (issue #2).
            let roomName = "\(VoiceConfig.roomName)-\(UUID().uuidString.prefix(8))"
            let creds = try await VoiceTokenService.fetch(room: roomName)
            room.add(delegate: self)   // receive "moment" data from the agent
            try await room.connect(url: creds.serverUrl, token: creds.token)
            // Publish the microphone. The LiveKit SDK owns AVAudioSession,
            // playback routing, and interruption handling from here on.
            try await room.localParticipant.setMicrophone(enabled: true)
            isMicEnabled = true
            state = .connected
            // Fallback: if we never see the agent join, treat as ready after a few
            // seconds so the UI doesn't get stuck on "waking".
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                await MainActor.run { self?.agentReady = true }
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// The agent (a remote participant) joined → it's now listening.
    nonisolated func room(_ room: Room, participantDidConnect participant: RemoteParticipant) {
        Task { @MainActor in self.agentReady = true }
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

    /// Stream live GPS distance + pace to the coach during an outdoor workout (#9).
    func sendGeo(distanceMeters: Double, pace: String?) async {
        var p: [String: Any] = ["type": "geo", "distance_m": distanceMeters]
        if let pace { p["pace"] = pace }
        await sendControl(p, topic: "geo")
    }

    /// Send the user's onboarding profile to the coach (#11) so it can tailor
    /// advice + generate today's plans.
    func sendProfile(_ profile: [String: Any]) async {
        var p = profile
        p["type"] = "profile"
        await sendControl(p, topic: "profile")
    }

    /// EXECUTION: tell the coach to start the workout. Pass the decided plan (from
    /// the Plan tab) so it coaches that instead of re-proposing.
    func sendWorkoutStarted(plan: String? = nil) async {
        var p: [String: Any] = ["type": "workout_started"]
        if let plan { p["plan"] = plan }
        await sendControl(p, topic: "workout_started")
    }

    /// PLANNING: ask the coach to discuss + decide the workout (Discuss Workout).
    func sendDiscussWorkout() async {
        await sendControl(["type": "discuss_workout"], topic: "discuss_workout")
    }

    /// Ask the coach to run the voice onboarding interview.
    func sendStartOnboarding() async {
        await sendControl(["type": "start_onboarding"], topic: "start_onboarding")
    }

    /// Ask the coach to compile + push this week's nutrition summary to the tab.
    func sendGetNutritionSummary() async {
        await sendControl(["type": "get_nutrition_summary"], topic: "get_nutrition_summary")
    }

    private let coarseLocator = CoarseLocator()

    /// Send the user's coarse location so the coach can do "near me" lookups
    /// (restaurants/gyms via nearby_places). Best-effort; silently skips if denied.
    func sendLocation() async {
        let loc: CLLocation? = await withCheckedContinuation { cont in
            coarseLocator.fetch { cont.resume(returning: $0) }
        }
        guard let loc else { return }
        var payload: [String: Any] = ["type": "location",
                                      "lat": loc.coordinate.latitude,
                                      "lng": loc.coordinate.longitude]
        if let place = try? await CLGeocoder().reverseGeocodeLocation(loc).first,
           let area = place.subLocality ?? place.locality {
            payload["area"] = area
        }
        await sendControl(payload, topic: "location")
    }

    /// A home-screen quick-action chip — kick off the conversation as if the user
    /// asked this out loud (the coach answers by voice).
    func sendAsk(_ text: String) async {
        await sendControl(["type": "ask", "text": text], topic: "ask")
    }

    /// Tell the coach the user's LOCAL time of day (it runs in cloud UTC).
    func sendLocalTime() async {
        let now = Date()
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        let isoDate = DateFormatter(); isoDate.dateFormat = "yyyy-MM-dd"
        let human = DateFormatter(); human.dateFormat = "EEEE, d MMMM yyyy"
        let hour = Calendar.current.component(.hour, from: now)
        let period = (5..<12).contains(hour) ? "morning"
            : (12..<17).contains(hour) ? "afternoon"
            : (17..<21).contains(hour) ? "evening" : "night"
        await sendControl(["type": "local_time", "time": f.string(from: now),
                           "date": isoDate.string(from: now),      // 2026-07-12 (absolute)
                           "date_str": human.string(from: now),    // Saturday, 12 July 2026
                           "period": period, "tz": TimeZone.current.identifier],
                          topic: "local_time")
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
        case "plans":
            struct Payload: Decodable { let plans: [CoachPlan] }
            guard let p = try? JSONDecoder().decode(Payload.self, from: data) else { return }
            Task { @MainActor in self.onPlans?(p.plans) }
        case "start_gps":
            Task { @MainActor in self.onStartGPS?() }
        case "handsfree":
            Task { @MainActor in self.onHandsfree?() }
        case "profile_saved":
            let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            Task { @MainActor in self.onProfileSaved?(obj) }
        case "workout_label":
            guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let label = obj["label"] as? String else { return }
            Task { @MainActor in self.onWorkoutLabel?(label) }
        case "nutrition_summary":
            guard let s = try? JSONDecoder().decode(NutritionSummary.self, from: data) else { return }
            Task { @MainActor in self.onNutritionSummary?(s) }
        case "results":
            guard let r = try? JSONDecoder().decode(AgentResults.self, from: data) else { return }
            Task { @MainActor in self.onResults?(r) }
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
    var onPlans: ((_ plans: [CoachPlan]) -> Void)?
    var onStartGPS: (() -> Void)?
    var onHandsfree: (() -> Void)?
    var onProfileSaved: ((_ profile: [String: Any]) -> Void)?
    var onWorkoutLabel: ((_ label: String) -> Void)?
    var onNutritionSummary: ((_ summary: NutritionSummary) -> Void)?
    var onResults: ((_ results: AgentResults) -> Void)?
    func sendKeepAlive() async {}
    func sendGeo(distanceMeters: Double, pace: String?) async {}
    func sendProfile(_ profile: [String: Any]) async {}
    func sendWorkoutStarted(plan: String? = nil) async {}
    func sendDiscussWorkout() async {}
    func sendStartOnboarding() async {}
    func sendGetNutritionSummary() async {}
    func sendAsk(_ text: String) async {}
    func sendLocation() async {}
    func sendLocalTime() async {}

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
