import SwiftUI
import AVFoundation

/// Dad OS Voice Chat View - Phase 8 - Audio-to-Audio with Gemini Live
/// Real-time audio conversations using Gemini 2.0 Flash Live API
struct DadVoiceChatView: View {
    // Audio Manager
    @StateObject private var audioManager = DadAudioManager()

    // Conversation State
    @State private var conversationType: ConversationType = .morningCheckin
    @State private var messages: [DadChatMessage] = []

    // UI State
    @State private var isConnecting: Bool = false
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""

    // Exercise Display
    @State private var selectedExercises: [[String: Any]] = []
    @State private var showExercises: Bool = false

    // User ID (TODO: Get from actual auth)
    private let userId = "00000000-0000-0000-0000-000000000001"

    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)

            VStack(spacing: 0) {
                // MARK: - Header
                headerView

                // MARK: - Conversation Type Picker
                conversationTypePicker

                // MARK: - Messages ScrollView (Text Transcript)
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 16) {
                            ForEach(messages) { message in
                                MessageBubble(message: message)
                                    .id(message.id)
                            }

                            // Connection status
                            if isConnecting {
                                HStack {
                                    Text("Connecting to Dad...")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .orange))
                                }
                                .padding()
                            }
                        }
                        .padding()
                    }
                    .onChange(of: messages.count) { _ in
                        if let lastMessage = messages.last {
                            withAnimation {
                                proxy.scrollTo(lastMessage.id, anchor: .bottom)
                            }
                        }
                    }
                }

                // MARK: - Exercise Display (if ready)
                if showExercises && !selectedExercises.isEmpty {
                    exerciseCarousel
                }

                // MARK: - Audio Controls
                audioControlsView
            }
        }
        .onAppear {
            requestMicrophonePermission()
        }
        .onDisappear {
            audioManager.disconnect()
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .onChange(of: audioManager.transcripts) { transcripts in
            // Update messages from audio manager
            messages = transcripts
        }
    }

    // MARK: - Header View
    private var headerView: some View {
        VStack(spacing: 4) {
            HStack {
                Text("DAD")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                // Connection indicator
                Circle()
                    .fill(audioManager.isConnected ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
            }

            Text("Voice Conversation • Gemini Live")
                .font(.caption)
                .foregroundColor(.gray)
                .tracking(1)
        }
        .padding(.top, 60)
        .padding(.bottom, 16)
    }

    // MARK: - Conversation Type Picker
    private var conversationTypePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ConversationTypeButton(
                    type: .morningCheckin,
                    isSelected: conversationType == .morningCheckin
                ) {
                    switchConversationType(.morningCheckin)
                }

                ConversationTypeButton(
                    type: .manualWorkout,
                    isSelected: conversationType == .manualWorkout
                ) {
                    switchConversationType(.manualWorkout)
                }

                ConversationTypeButton(
                    type: .workoutAnnotation,
                    isSelected: conversationType == .workoutAnnotation
                ) {
                    switchConversationType(.workoutAnnotation)
                }
            }
            .padding(.horizontal)
        }
        .padding(.bottom, 12)
    }

    // MARK: - Exercise Carousel
    private var exerciseCarousel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your Workout")
                .font(.headline)
                .foregroundColor(.white)
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(selectedExercises.indices, id: \.self) { index in
                        ExerciseCard(exercise: selectedExercises[index])
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.05))
    }

    // MARK: - Audio Controls
    private var audioControlsView: some View {
        VStack(spacing: 16) {
            // Waveform visualization
            if audioManager.isRecording {
                WaveformView(audioLevel: audioManager.audioLevel)
                    .frame(height: 60)
                    .padding(.horizontal)
            }

            // Main microphone button
            HStack(spacing: 40) {
                // Connection status text
                VStack {
                    if audioManager.isConnected {
                        if audioManager.isRecording {
                            Text("Listening...")
                                .font(.caption)
                                .foregroundColor(.orange)
                        } else if audioManager.isSpeaking {
                            Text("Dad is speaking...")
                                .font(.caption)
                                .foregroundColor(.green)
                        } else {
                            Text("Tap to speak")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                }
                .frame(minWidth: 100)

                // Microphone button
                Button(action: {
                    if audioManager.isConnected {
                        if audioManager.isRecording {
                            audioManager.stopRecording()
                        } else {
                            audioManager.startRecording()
                        }
                    } else {
                        connectToCloud()
                    }
                }) {
                    ZStack {
                        // Pulse animation when recording
                        if audioManager.isRecording {
                            Circle()
                                .fill(RadialGradient(
                                    gradient: Gradient(colors: [.orange.opacity(0.6), .clear]),
                                    center: .center,
                                    startRadius: 50,
                                    endRadius: 100
                                ))
                                .frame(width: 150, height: 150)
                                .scaleEffect(audioManager.audioLevel > 0.1 ? 1.2 : 0.8)
                                .animation(.easeInOut(duration: 0.3), value: audioManager.audioLevel)
                        }

                        Circle()
                            .fill(LinearGradient(
                                gradient: Gradient(colors: audioManager.isRecording ? [.orange, .red] : [.blue, .purple]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                            .frame(width: 100, height: 100)
                            .shadow(color: audioManager.isRecording ? .orange.opacity(0.6) : .blue.opacity(0.5), radius: 20, x: 0, y: 10)

                        Image(systemName: audioManager.isRecording ? "waveform" : "mic.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.white)
                    }
                }
                .disabled(isConnecting || audioManager.isSpeaking)

                // Done Speaking button - appears when recording
                if audioManager.isRecording {
                    Button(action: {
                        audioManager.sendDoneSpeaking()
                    }) {
                        VStack {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 30))
                                .foregroundColor(.green)
                            Text("Done")
                                .font(.caption)
                                .foregroundColor(.white)
                        }
                        .padding()
                        .background(Color.green.opacity(0.2))
                        .cornerRadius(15)
                    }
                }

                // Disconnect button
                if audioManager.isConnected {
                    Button(action: {
                        audioManager.disconnect()
                        messages = []
                        selectedExercises = []
                    }) {
                        VStack {
                            Image(systemName: "phone.down.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.red)
                            Text("End")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                } else {
                    Spacer()
                        .frame(width: 60)
                }
            }
            .padding(.vertical, 20)
        }
        .background(Color(UIColor.systemGray6))
    }

    // MARK: - Actions

    private func switchConversationType(_ newType: ConversationType) {
        conversationType = newType
        audioManager.disconnect()
        messages = []
        selectedExercises = []
        showExercises = false
    }

    private func requestMicrophonePermission() {
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            if !granted {
                DispatchQueue.main.async {
                    errorMessage = "Microphone permission is required for voice conversations"
                    showError = true
                }
            }
        }
    }

    private func connectToCloud() {
        isConnecting = true

        audioManager.connect(
            userId: userId,
            conversationType: conversationType.rawValue
        ) { success, error in
            DispatchQueue.main.async {
                isConnecting = false

                if !success {
                    errorMessage = error ?? "Failed to connect to Dad"
                    showError = true
                }
            }
        }
    }
}

// MARK: - Audio Manager

class DadAudioManager: NSObject, ObservableObject {
    // Connection state
    @Published var isConnected: Bool = false
    @Published var isRecording: Bool = false
    @Published var isSpeaking: Bool = false
    @Published var audioLevel: Float = 0.0
    @Published var transcripts: [DadChatMessage] = []

    // WebSocket
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?

    // Audio components
    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private var audioPlayer: AVAudioPlayer?
    private var playerNode: AVAudioPlayerNode?
    private var audioFormat: AVAudioFormat?
    private var audioConverter: AVAudioConverter?

    // Removed: Silence detection - Gemini's automatic VAD handles turn-taking

    // Cloud Run URL
    private let cloudRunURL = "wss://dad-live-audio-zupjde2jpq-uc.a.run.app/ws"

    override init() {
        super.init()
        setupAudioSession()
    }

    private func setupAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try audioSession.setActive(true)
        } catch {
            print("❌ Failed to setup audio session: \(error)")
        }
    }

    // MARK: - WebSocket Connection

    func connect(userId: String, conversationType: String, completion: @escaping (Bool, String?) -> Void) {
        guard let url = URL(string: cloudRunURL) else {
            completion(false, "Invalid Cloud Run URL")
            return
        }

        urlSession = URLSession(configuration: .default, delegate: self, delegateQueue: OperationQueue())
        webSocketTask = urlSession?.webSocketTask(with: url)
        webSocketTask?.resume()

        // Send start message
        let startMessage: [String: Any] = [
            "action": "start",
            "user_id": userId,
            "conversation_type": conversationType
        ]

        if let jsonData = try? JSONSerialization.data(withJSONObject: startMessage),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            webSocketTask?.send(.string(jsonString)) { error in
                if let error = error {
                    print("❌ Failed to send start message: \(error)")
                    completion(false, error.localizedDescription)
                } else {
                    print("✅ Start message sent")
                    DispatchQueue.main.async {
                        self.isConnected = true
                    }
                    completion(true, nil)

                    // Start receiving messages
                    self.receiveMessage()

                    // Auto-start recording after connection
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.startRecording()
                    }
                }
            }
        }
    }

    func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        audioEngine?.stop()
        audioEngine = nil

        DispatchQueue.main.async {
            self.isConnected = false
            self.isRecording = false
            self.isSpeaking = false
        }
    }

    func sendDoneSpeaking() {
        // Send end_input signal to backend
        let endMessage: [String: Any] = [
            "action": "end_input"
        ]

        if let jsonData = try? JSONSerialization.data(withJSONObject: endMessage),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            webSocketTask?.send(.string(jsonString)) { error in
                if let error = error {
                    print("❌ Failed to send end_input: \(error)")
                } else {
                    print("✅ end_input signal sent - Gemini should respond now")

                    // Stop recording to stop sending more audio
                    DispatchQueue.main.async {
                        self.stopRecording()
                    }
                }
            }
        }
    }

    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let message):
                switch message {
                case .data(let data):
                    // Audio data from Gemini
                    print("📥 Received audio from Gemini: \(data.count) bytes")
                    self.playAudio(data: data)

                case .string(let text):
                    // JSON message (transcript, status, etc.)
                    print("📥 Received JSON from backend: \(text)")
                    if let data = text.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        self.handleJSONMessage(json)
                    }

                @unknown default:
                    break
                }

                // Continue receiving
                self.receiveMessage()

            case .failure(let error):
                print("❌ WebSocket receive error: \(error)")

                // Clean up recording when connection fails
                if self.isRecording {
                    self.stopRecording()
                }

                DispatchQueue.main.async {
                    self.isConnected = false
                }
            }
        }
    }

    private func handleJSONMessage(_ json: [String: Any]) {
        if let type = json["type"] as? String {
            if type == "transcript" {
                if let text = json["text"] as? String,
                   let isDad = json["is_dad"] as? Bool {
                    DispatchQueue.main.async {
                        self.transcripts.append(DadChatMessage(text: text, isFromDad: isDad))
                    }
                }
            }
        }
    }

    // MARK: - Audio Recording

    func startRecording() {
        // Initialize shared audio engine if not already created
        if audioEngine == nil {
            audioEngine = AVAudioEngine()

            // Set up player node for playback on same engine
            playerNode = AVAudioPlayerNode()
            let playbackFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 24000, channels: 1, interleaved: false)!
            audioEngine?.attach(playerNode!)
            audioEngine?.connect(playerNode!, to: audioEngine!.mainMixerNode, format: playbackFormat)
        }

        inputNode = audioEngine?.inputNode
        guard let inputNode = inputNode else { return }

        let recordingFormat = inputNode.outputFormat(forBus: 0)

        // Remove any existing tap before installing new one
        if inputNode.numberOfInputs > 0 {
            inputNode.removeTap(onBus: 0)
        }

        // Create Gemini's required format: 16kHz, PCM16, mono
        guard let geminiFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: false) else {
            print("❌ Failed to create Gemini audio format")
            return
        }

        // Create converter from iPhone format to Gemini format
        guard let converter = AVAudioConverter(from: recordingFormat, to: geminiFormat) else {
            print("❌ Failed to create audio converter")
            return
        }
        self.audioConverter = converter

        // Install tap to capture audio
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: recordingFormat) { [weak self] buffer, time in
            guard let self = self else { return }

            // Calculate audio level for visualization (before conversion)
            let level = self.calculateAudioLevel(buffer: buffer)
            DispatchQueue.main.async {
                self.audioLevel = level
            }

            // Convert buffer to Gemini format and send to WebSocket
            if let convertedData = self.convertAndBufferToData(buffer: buffer, converter: converter, targetFormat: geminiFormat) {
                self.sendAudioData(convertedData)
            }
        }
        do {
            try audioEngine?.start()
            DispatchQueue.main.async {
                self.isRecording = true
            }
            print("🎙️ Recording started (converting to 16kHz PCM16 mono for Gemini)")
        } catch {
            print("❌ Failed to start recording: \(error)")
        }
    }

    func stopRecording() {
        // Only remove tap, keep engine running for playback
        inputNode?.removeTap(onBus: 0)

        DispatchQueue.main.async {
            self.isRecording = false
            self.audioLevel = 0.0
        }

        print("🛑 Recording stopped")
    }

    // MARK: - Audio Streaming

    private func sendAudioData(_ data: Data) {
        // Debug: Log every 50th chunk to avoid spam
        if Int.random(in: 1...50) == 1 {
            print("📤 Sending audio chunk: \(data.count) bytes (16kHz PCM16)")
        }

        webSocketTask?.send(.data(data)) { error in
            if let error = error {
                print("❌ Failed to send audio data: \(error)")
            }
        }
    }

    private func bufferToData(buffer: AVAudioPCMBuffer) -> Data? {
        let audioBuffer = buffer.audioBufferList.pointee.mBuffers
        return Data(bytes: audioBuffer.mData!, count: Int(audioBuffer.mDataByteSize))
    }

    private func convertAndBufferToData(buffer: AVAudioPCMBuffer, converter: AVAudioConverter, targetFormat: AVAudioFormat) -> Data? {
        // Calculate the converted buffer capacity
        // Conversion ratio: (targetSampleRate / sourceSampleRate) * sourceFrameLength
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let convertedFrameCapacity = UInt32(Double(buffer.frameLength) * ratio)

        guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: convertedFrameCapacity) else {
            print("❌ Failed to create converted buffer")
            return nil
        }

        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }

        let status = converter.convert(to: convertedBuffer, error: &error, withInputFrom: inputBlock)

        if let error = error {
            print("❌ Audio conversion error: \(error)")
            return nil
        }

        if status == .error {
            print("❌ Conversion failed with error status")
            return nil
        }

        // IMPORTANT: Use the actual frame length after conversion
        convertedBuffer.frameLength = convertedBuffer.frameCapacity

        if convertedBuffer.frameLength == 0 {
            print("❌ No frames converted")
            return nil
        }

        // Get PCM16 data - for mono, it's in int16ChannelData
        guard let pcm16Data = convertedBuffer.int16ChannelData?[0] else {
            print("❌ Failed to get PCM16 channel data")
            return nil
        }

        // Convert to Data
        let frameCount = Int(convertedBuffer.frameLength)
        let byteCount = frameCount * 2  // 2 bytes per PCM16 sample
        let data = Data(bytes: pcm16Data, count: byteCount)

        // Debug
        if Int.random(in: 1...50) == 1 {
            let sample = data.prefix(20)
            print("🔍 Converted audio (\(frameCount) frames, \(byteCount) bytes): \(sample.map { String(format: "%02x", $0) }.joined())")
        }

        return data
    }

    private func calculateAudioLevel(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0.0 }

        let channelDataValue = channelData.pointee
        let frameLength = UInt(buffer.frameLength)

        var sum: Float = 0.0
        for i in 0..<Int(frameLength) {
            sum += abs(channelDataValue[i])
        }

        let average = sum / Float(frameLength)
        return min(average * 10, 1.0) // Normalize and cap at 1.0
    }

    // MARK: - Audio Playback

    private func playAudio(data: Data) {
        guard let playerNode = playerNode, let audioEngine = audioEngine else {
            print("❌ Audio engine not initialized")
            return
        }

        DispatchQueue.main.async {
            self.isSpeaking = true
        }

        // Gemini sends PCM audio at 24kHz, mono, 16-bit linear PCM
        let sampleRate: Double = 24000
        guard let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: sampleRate, channels: 1, interleaved: false) else {
            print("❌ Failed to create audio format")
            DispatchQueue.main.async { self.isSpeaking = false }
            return
        }

        let frameCount = UInt32(data.count) / format.streamDescription.pointee.mBytesPerFrame
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            print("❌ Failed to create PCM buffer")
            DispatchQueue.main.async { self.isSpeaking = false }
            return
        }

        buffer.frameLength = frameCount
        data.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) in
            guard let baseAddress = ptr.baseAddress else { return }
            buffer.int16ChannelData?.pointee.update(from: baseAddress.assumingMemoryBound(to: Int16.self), count: Int(frameCount))
        }

        // Schedule and play buffer on existing player node
        playerNode.scheduleBuffer(buffer) {
            DispatchQueue.main.async {
                self.isSpeaking = false
            }
        }

        if !playerNode.isPlaying {
            playerNode.play()
        }
    }
}

// MARK: - AVAudioPlayerDelegate

extension DadAudioManager: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.isSpeaking = false
        }
    }
}

// MARK: - URLSessionWebSocketDelegate

extension DadAudioManager: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        print("✅ WebSocket connected")
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        print("🔌 WebSocket disconnected")
        DispatchQueue.main.async {
            self.isConnected = false
        }
    }
}

// MARK: - Waveform View

struct WaveformView: View {
    let audioLevel: Float

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<20) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.orange)
                    .frame(width: 3, height: CGFloat(audioLevel) * 60 * CGFloat.random(in: 0.5...1.0))
            }
        }
        .animation(.easeInOut(duration: 0.1), value: audioLevel)
    }
}

// MARK: - Supporting Types (keeping from original)

enum ConversationType: String {
    case morningCheckin = "morning_checkin"
    case manualWorkout = "manual_workout_logging"
    case workoutAnnotation = "workout_annotation"

    var displayName: String {
        switch self {
        case .morningCheckin: return "Check-in"
        case .manualWorkout: return "Log Workout"
        case .workoutAnnotation: return "Annotate"
        }
    }

    var icon: String {
        switch self {
        case .morningCheckin: return "sun.horizon.fill"
        case .manualWorkout: return "pencil"
        case .workoutAnnotation: return "note.text"
        }
    }
}

struct DadChatMessage: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let isFromDad: Bool
    let isSystem: Bool
    let timestamp: Date

    init(text: String, isFromDad: Bool, isSystem: Bool = false) {
        self.text = text
        self.isFromDad = isFromDad
        self.isSystem = isSystem
        self.timestamp = Date()
    }

    static func == (lhs: DadChatMessage, rhs: DadChatMessage) -> Bool {
        lhs.id == rhs.id
    }
}

struct MessageBubble: View {
    let message: DadChatMessage

    var body: some View {
        HStack {
            if !message.isFromDad && !message.isSystem {
                Spacer()
            }

            VStack(alignment: message.isFromDad ? .leading : .trailing, spacing: 4) {
                if message.isSystem {
                    Text(message.text)
                        .font(.caption)
                        .foregroundColor(.green)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(8)
                } else {
                    Text(message.text)
                        .font(.body)
                        .foregroundColor(message.isFromDad ? .white : .black)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(message.isFromDad ? Color.orange : Color.white)
                        .cornerRadius(16)

                    Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
            }

            if message.isFromDad && !message.isSystem {
                Spacer()
            }
        }
    }
}

struct ConversationTypeButton: View {
    let type: ConversationType
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: type.icon)
                    .font(.system(size: 20))
                    .foregroundColor(isSelected ? .white : .gray)

                Text(type.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(isSelected ? .white : .gray)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(isSelected ? Color.orange : Color.white.opacity(0.1))
            .cornerRadius(12)
        }
    }
}

struct ExerciseCard: View {
    let exercise: [String: Any]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let images = exercise["images"] as? [String],
               let firstImageURL = images.first,
               let url = URL(string: firstImageURL) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .frame(width: 200, height: 150)
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 200, height: 150)
                            .clipped()
                    case .failure:
                        Image(systemName: "dumbbell.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.gray)
                            .frame(width: 200, height: 150)
                    @unknown default:
                        EmptyView()
                    }
                }
                .cornerRadius(12)
            } else {
                ZStack {
                    Color.white.opacity(0.1)
                    Image(systemName: "dumbbell.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.gray)
                }
                .frame(width: 200, height: 150)
                .cornerRadius(12)
            }

            Text(exercise["name"] as? String ?? "Exercise")
                .font(.headline)
                .foregroundColor(.white)
                .lineLimit(2)

            if let equipment = exercise["equipment"] as? String {
                Text(equipment)
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .frame(width: 200)
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(16)
    }
}

struct DadVoiceChatView_Previews: PreviewProvider {
    static var previews: some View {
        DadVoiceChatView()
    }
}
