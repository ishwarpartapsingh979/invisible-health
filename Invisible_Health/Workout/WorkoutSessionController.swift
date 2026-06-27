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

    /// Set by the view to forward each sample onward (e.g. to the agent).
    var heartRateSink: ((HeartRateSample) -> Void)?

    private var provider: LiveHeartRateProvider?
    private var staleTimer: Timer?
    private var lastSampleAt: Date?

    func startWorkout() {
        guard !isActive else { return }
        isActive = true
        lastSampleAt = nil
        currentBPM = nil

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
    }

    func stopWorkout() {
        isActive = false
        provider?.stop()
        provider = nil
        staleTimer?.invalidate()
        staleTimer = nil
        currentBPM = nil
        hrState = .idle
    }

    // MARK: - Internals

    private func handle(_ sample: HeartRateSample) {
        currentBPM = sample.bpm
        worn = sample.worn
        lastSampleAt = sample.timestamp
        if hrState != .streaming { hrState = .streaming }
        heartRateSink?(sample)
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
