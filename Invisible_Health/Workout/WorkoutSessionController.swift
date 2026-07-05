import Foundation
import Combine

/// Owns a workout's live-HR session: picks the right provider, surfaces BPM +
/// connection state to the UI, and forwards every sample to a sink (the LiveKit
/// data channel → agent). No LiveKit dependency, so it builds with or without
/// the SDK.
@MainActor
final class WorkoutSessionController: ObservableObject {

    @Published private(set) var isActive = false
    @Published private(set) var currentBPM: Int?
    @Published private(set) var worn = true
    @Published private(set) var hrState: HRConnectionState = .idle

    /// Live outdoor distance (meters) + pace, from GPS (nil indoors/treadmill).
    @Published private(set) var distanceMeters: Double = 0
    @Published private(set) var pace: String?

    /// Set by the view to forward GPS distance/pace to the agent (#9).
    var geoSink: ((_ distanceMeters: Double, _ pace: String?) -> Void)?
    private let location = LocationProvider()

    /// Set by the view to forward each sample onward (e.g. to the agent).
    var heartRateSink: ((HeartRateSample) -> Void)?

    /// Set by the view to (re)send the Whoop snapshot to the agent. Called on
    /// start and every few seconds — the periodic re-send survives the agent
    /// joining the room a beat after connect, and picks up data once Open
    /// Wearables finishes syncing.
    var whoopContextSink: (() -> Void)?

    /// Set by the view (only when the wake word is armed) to (re)send the
    /// "enter wake mode" signal to the agent. Re-sent on the same cadence as the
    /// Whoop snapshot because, like it, a one-shot send is lost when the agent
    /// joins the room a beat after we connect — which would leave the agent in
    /// always-on mode, responding to everything instead of sleeping until
    /// "Hey Coach". Entering wake mode on the agent is idempotent, so re-sends
    /// are harmless and also re-arm it if the agent ever reconnects mid-workout.
    var wakeModeSink: (() -> Void)?

    // MARK: - Recording (for the post-workout review graph)

    /// When the current workout started; the origin for all `t` offsets.
    private(set) var startedAt: Date?
    /// Down-sampled HR series for the graph (a point every `hrLogInterval`s).
    private(set) var hrLog: [HRSample] = []
    /// Spoken moments captured by the agent (transcript + breathing analysis +
    /// HR), surfaced for the UI and saved with the workout.
    @Published private(set) var moments: [WorkoutMoment] = []

    private let hrLogInterval: TimeInterval = 15
    private var lastHRLoggedT: TimeInterval = -.greatestFiniteMagnitude

    private var provider: LiveHeartRateProvider?
    private var staleTimer: Timer?
    private var whoopTimer: Timer?
    private var lastSampleAt: Date?

    /// Called by the view when a "moment" arrives from the agent over the data
    /// channel. Pins it to the workout timeline so it lines up with the HR graph.
    func recordMoment(transcript: String, analysis: String, bpm: Int?) {
        guard isActive, let startedAt else { return }
        moments.append(WorkoutMoment(
            t: Date().timeIntervalSince(startedAt),
            bpm: bpm, transcript: transcript, analysis: analysis))
    }

    func startWorkout() {
        guard !isActive else { return }
        isActive = true
        lastSampleAt = nil
        currentBPM = nil
        startedAt = Date()
        hrLog = []
        moments = []
        lastHRLoggedT = -.greatestFiniteMagnitude

        let p = makeProvider()
        p.onStateChange = { [weak self] state in
            Task { @MainActor in self?.hrState = state }
        }
        p.onSample = { [weak self] sample in
            Task { @MainActor in self?.handle(sample) }
        }
        provider = p
        p.start()
        startStaleWatchdog()
        startWhoopBroadcast()

        // Live outdoor distance/pace (GPS). NOT started here — only when the coach
        // signals an outdoor run (see startLocation), so indoor/gym workouts don't
        // trigger a location prompt or waste battery.
        distanceMeters = 0
        pace = nil
        location.onUpdate = { [weak self] dist, pace in
            Task { @MainActor in
                guard let self, self.isActive else { return }
                self.distanceMeters = dist
                self.pace = pace
                self.geoSink?(dist, pace)
            }
        }
    }

    /// Begin GPS tracking — called only when the coach detects an outdoor run
    /// (triggers the location-permission prompt at that point).
    func startLocation() {
        guard isActive else { return }
        location.start()
    }

    func stopWorkout() {
        isActive = false
        provider?.stop()
        provider = nil
        location.stop()
        staleTimer?.invalidate()
        staleTimer = nil
        whoopTimer?.invalidate()
        whoopTimer = nil
        currentBPM = nil
        hrState = .idle
    }

    /// Send the Whoop snapshot now, then every 5s while active — so it reaches
    /// the agent even if it joined the room just after we connected.
    private func startWhoopBroadcast() {
        whoopContextSink?()
        wakeModeSink?()
        whoopTimer?.invalidate()
        whoopTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isActive else { return }
                self.whoopContextSink?()
                self.wakeModeSink?()
            }
        }
    }

    // MARK: - Internals

    private func handle(_ sample: HeartRateSample) {
        currentBPM = sample.bpm
        worn = sample.worn
        lastSampleAt = sample.timestamp
        if hrState != .streaming { hrState = .streaming }
        heartRateSink?(sample)

        // Down-sample into the graph series: one point per hrLogInterval.
        if let startedAt {
            let t = sample.timestamp.timeIntervalSince(startedAt)
            if t - lastHRLoggedT >= hrLogInterval {
                lastHRLoggedT = t
                hrLog.append(HRSample(t: t, bpm: sample.bpm))
            }
        }
    }

    /// Build a persistable log from the just-finished workout. Returns nil if
    /// there's nothing worth saving (no HR samples and no moments).
    func makeLog() -> WorkoutLog? {
        guard let startedAt, !hrLog.isEmpty || !moments.isEmpty else { return nil }
        return WorkoutLog(start: startedAt, end: Date(), hr: hrLog, moments: moments)
    }

    private func makeProvider() -> LiveHeartRateProvider {
        #if targetEnvironment(simulator)
        return SimulatedHRProvider()
        #else
        return WhoopBLEProvider()
        #endif
    }

    /// If samples stop arriving for >5s, clear the BPM so nothing acts on a
    /// stale reading.
    private func startStaleWatchdog() {
        staleTimer?.invalidate()
        staleTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isActive, let last = self.lastSampleAt else { return }
                if Date().timeIntervalSince(last) > 5 {
                    self.currentBPM = nil
                    if self.hrState == .streaming { self.hrState = .disconnected }
                }
            }
        }
    }
}
