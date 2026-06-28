import Foundation

/// On-device "Hey Coach" wake-word detection using LiveKit's open-source
/// wake-word engine (github.com/livekit/livekit-wakeword — Apache 2.0, ONNX,
/// CoreML-accelerated). 100% on-device; nothing leaves the phone until the user
/// says the wake word and we open the agent's ears.
///
/// It taps the microphone audio LiveKit already captures — via
/// `AudioManager.shared.capturePostProcessingDelegate` — so there's exactly ONE
/// owner of the mic (the LiveKit room). We do NOT use `WakeWordListener` (which
/// opens its own AVAudioEngine mic and would fight the room); instead we score
/// frames manually with `WakeWordModel.predict`.
///
/// Pipeline: capture frames → resample to 16 kHz mono Int16 → rolling 2-second
/// ring buffer → periodic background `predict()` → threshold + debounce → onWake.
///
/// Guarded by `#if canImport(LiveKitWakeWord)` so the app keeps building before
/// the SPM package + hey_coach.onnx are added (see WakeWordConfig). Until then
/// `WakeWordDetector(onWake:)` returns nil and workouts stay always-on.

#if canImport(LiveKit) && canImport(LiveKitWakeWord)
import AVFoundation
import LiveKit
import LiveKitWakeWord

final class WakeWordDetector: NSObject, AudioCustomProcessingDelegate {

    static let isSupported = true

    private let onWake: () -> Void
    private let model: WakeWordModel
    private let threshold: Float

    // predict() wants ~2s of 16 kHz mono Int16. We keep a rolling window.
    private let modelRate: Double = 16000
    private let windowSeconds = 2.0
    private var ringCapacity: Int { Int(modelRate * windowSeconds) }
    private var ring: [Int16] = []
    private let ringLock = NSLock()

    // Resample LiveKit's capture audio → 16 kHz mono Int16.
    private let outputFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true)!
    private var converter: AVAudioConverter?
    private var inputFormat: AVAudioFormat?

    // Inference runs off the audio thread on a serial queue (predict() calls must
    // not overlap), with a debounce so one utterance fires once.
    private let inferQueue = DispatchQueue(label: "wakeword.infer", qos: .userInitiated)
    private var timer: DispatchSourceTimer?
    private let predictInterval: TimeInterval = 0.12
    private let debounce: TimeInterval = 1.5
    private var lastFireAt = Date.distantPast

    init?(onWake: @escaping () -> Void) {
        guard let url = WakeWordConfig.modelURL else {
            print("WakeWord: \(WakeWordConfig.modelResource).onnx not bundled — skipping.")
            return nil
        }
        self.onWake = onWake
        self.threshold = WakeWordConfig.threshold
        do {
            // CPU execution provider on purpose: the coach must keep listening
            // while the app is backgrounded / screen-locked during a workout,
            // and iOS forbids GPU (Metal/CoreML) work from a background app
            // (IOGPUMetalError: BackgroundExecutionNotPermitted). The wake-word
            // model is tiny, so CPU inference is fast enough and works anywhere.
            model = try WakeWordModel(models: [url], sampleRate: 16000, executionProvider: .cpu)
        } catch {
            print("WakeWord: model init failed: \(error)")
            return nil
        }
        super.init()
        startInferenceLoop()
    }

    func stop() {
        timer?.cancel()
        timer = nil
        ringLock.lock(); ring.removeAll(); ringLock.unlock()
    }

    private func startInferenceLoop() {
        let t = DispatchSource.makeTimerSource(queue: inferQueue)
        t.schedule(deadline: .now() + 0.5, repeating: predictInterval)
        t.setEventHandler { [weak self] in self?.runInference() }
        t.resume()
        timer = t
    }

    private func runInference() {
        ringLock.lock()
        guard ring.count >= ringCapacity else { ringLock.unlock(); return }
        let snapshot = ring
        ringLock.unlock()

        guard let scores = try? model.predict(snapshot) else { return }
        let maxScore = scores.values.max() ?? 0
        if maxScore >= threshold, Date().timeIntervalSince(lastFireAt) > debounce {
            lastFireAt = Date()
            DispatchQueue.main.async { [weak self] in self?.onWake() }
        }
    }

    // MARK: - AudioCustomProcessingDelegate

    func audioProcessingInitialize(sampleRate: Int, channels: Int) {
        ringLock.lock(); ring.removeAll(keepingCapacity: true); ringLock.unlock()
    }

    func audioProcessingProcess(audioBuffer: LKAudioBuffer) {
        guard let inBuf = audioBuffer.toAVAudioPCMBuffer() else { return }

        if converter == nil || inputFormat != inBuf.format {
            inputFormat = inBuf.format
            converter = AVAudioConverter(from: inBuf.format, to: outputFormat)
        }
        guard let converter else { return }

        let ratio = outputFormat.sampleRate / inBuf.format.sampleRate
        let capacity = AVAudioFrameCount(Double(inBuf.frameLength) * ratio) + 16
        guard let outBuf = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity)
        else { return }

        var fed = false
        var convErr: NSError?
        converter.convert(to: outBuf, error: &convErr) { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true
            status.pointee = .haveData
            return inBuf
        }
        guard convErr == nil, let ch = outBuf.int16ChannelData else { return }

        // Append the new samples and trim to the last 2 seconds. Cheap relative
        // to inference, so it's fine on the audio thread.
        ringLock.lock()
        ring.append(contentsOf: UnsafeBufferPointer(start: ch[0], count: Int(outBuf.frameLength)))
        if ring.count > ringCapacity {
            ring.removeFirst(ring.count - ringCapacity)
        }
        ringLock.unlock()
    }

    func audioProcessingRelease() {
        converter = nil
        inputFormat = nil
        ringLock.lock(); ring.removeAll(); ringLock.unlock()
    }
}

#else

/// Stub used until the LiveKitWakeWord SPM package + hey_coach.onnx are added.
/// Keeps the app compiling; workouts fall back to always-on listening.
final class WakeWordDetector {
    static let isSupported = false
    init?(onWake: @escaping () -> Void) { return nil }
    func stop() {}
}

#endif
