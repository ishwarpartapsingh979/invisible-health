import Foundation

#if targetEnvironment(simulator)
/// Fake heart-rate source for the iOS Simulator, where CoreBluetooth (and thus
/// the real Whoop) is unavailable. Lets the full pipeline — UI → LiveKit data
/// channel → agent — be exercised without any hardware. Compiled only for the
/// Simulator.
final class SimulatedHRProvider: LiveHeartRateProvider {
    var onSample: ((HeartRateSample) -> Void)?
    var onStateChange: ((HRConnectionState) -> Void)?

    private var timer: Timer?
    private var bpm = 92.0

    func start() {
        onStateChange?(.scanning)
        // Brief "connecting" then stream ~1 Hz, like a real strap.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self else { return }
            self.onStateChange?(.streaming)
            self.timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                guard let self else { return }
                // Random walk in a believable range.
                self.bpm += Double.random(in: -4...5)
                self.bpm = min(175, max(70, self.bpm))
                self.onSample?(HeartRateSample(bpm: Int(self.bpm.rounded()),
                                               worn: true,
                                               timestamp: Date()))
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        onStateChange?(.idle)
    }
}
#endif
