import Foundation

/// One live heart-rate reading.
struct HeartRateSample: Equatable {
    let bpm: Int
    let worn: Bool
    let timestamp: Date
}

/// Connection/streaming state of a heart-rate source.
enum HRConnectionState: Equatable {
    case idle
    case scanning      // looking for the Whoop
    case connecting
    case streaming     // receiving samples
    case disconnected  // dropped; trying to recover
    case unsupported   // Bluetooth off/unavailable on this device
    case unauthorized  // Bluetooth permission denied
}

/// A source of live heart rate. Two implementations:
///   • `WhoopBLEProvider`      — real Whoop strap over CoreBluetooth (device only)
///   • `SimulatedHRProvider`   — fake samples for the Simulator / pipeline tests
///
/// Keeping this protocol source-agnostic is what lets the Apple Watch path (and
/// later the dad's-rules engine) plug into the exact same stream.
protocol LiveHeartRateProvider: AnyObject {
    var onSample: ((HeartRateSample) -> Void)? { get set }
    var onStateChange: ((HRConnectionState) -> Void)? { get set }
    func start()
    func stop()
}
