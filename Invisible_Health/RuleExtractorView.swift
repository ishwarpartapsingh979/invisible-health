import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

// MARK: - Data Models

struct RuleExtractionResponse: Codable {
    let success: Bool
    let transcript: String?
    let extracted_rule: ExtractedRule?
    let rule_id: String?
    let audio_url: String?
    let message: String?
    let error: String?
    let stage: String?
}

struct ExtractedRule: Codable {
    let trigger_conditions: [String: AnyCodable]
    let action_vetoes: [String]
    let action_forces: [String]
    let veteran_rationale: String
}

// Helper to decode dynamic JSON values
struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else {
            value = ""
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        if let string = value as? String {
            try container.encode(string)
        } else if let int = value as? Int {
            try container.encode(int)
        } else if let double = value as? Double {
            try container.encode(double)
        } else if let bool = value as? Bool {
            try container.encode(bool)
        }
    }
}

// MARK: - Main View

struct RuleExtractorView: View {
    @State private var isRecording = false
    @State private var audioRecorder: AVAudioRecorder?
    @State private var recordedAudioURL: URL?

    @State private var processingStage: String = ""
    @State private var isProcessing = false

    @State private var extractionResult: RuleExtractionResponse?
    @State private var showResult = false
    @State private var errorMessage: String?

    @State private var showFilePicker = false
    @State private var pulseAnimation = false

    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)

            ScrollView {
                VStack(spacing: 30) {
                    // Header
                    VStack(spacing: 10) {
                        Text("DAD OS RULE EXTRACTOR")
                            .font(.title2)
                            .fontWeight(.bold)
                            .tracking(2)
                            .foregroundColor(.white)

                        Text("Voice → Rule Pipeline")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .padding(.top, 40)

                    // Processing Stage Indicator
                    if isProcessing {
                        ProcessingIndicator(stage: processingStage)
                    }

                    // Recording Section
                    if !showResult {
                        VStack(spacing: 20) {
                            // Record Button
                            Button(action: {
                                if isRecording {
                                    stopRecording()
                                } else {
                                    startRecording()
                                }
                            }) {
                                ZStack {
                                    // Pulse animation when recording
                                    if isRecording {
                                        Circle()
                                            .fill(RadialGradient(
                                                gradient: Gradient(colors: [.red.opacity(0.6), .clear]),
                                                center: .center,
                                                startRadius: 50,
                                                endRadius: 100
                                            ))
                                            .frame(width: 180, height: 180)
                                            .scaleEffect(pulseAnimation ? 1.3 : 0.9)
                                            .opacity(pulseAnimation ? 0.0 : 0.8)
                                            .animation(Animation.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: pulseAnimation)
                                    }

                                    Circle()
                                        .fill(LinearGradient(
                                            gradient: Gradient(colors: isRecording ? [.red, .orange] : [.blue, .purple]),
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ))
                                        .frame(width: 120, height: 120)
                                        .shadow(color: isRecording ? .red.opacity(0.5) : .blue.opacity(0.5), radius: 15)

                                    VStack {
                                        Image(systemName: isRecording ? "stop.circle.fill" : "mic.fill")
                                            .font(.system(size: 40))
                                            .foregroundColor(.white)

                                        if isRecording {
                                            Text("RECORDING")
                                                .font(.caption2)
                                                .fontWeight(.bold)
                                                .foregroundColor(.white)
                                        }
                                    }
                                }
                            }
                            .disabled(isProcessing)
                            .onAppear {
                                if isRecording {
                                    pulseAnimation = true
                                }
                            }

                            Text(isRecording ? "Tap to stop recording" : "Record coach's voice note")
                                .font(.caption)
                                .foregroundColor(.gray)

                            // OR divider
                            HStack {
                                Rectangle()
                                    .fill(Color.gray.opacity(0.3))
                                    .frame(height: 1)
                                Text("OR")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                Rectangle()
                                    .fill(Color.gray.opacity(0.3))
                                    .frame(height: 1)
                            }
                            .padding(.horizontal, 40)

                            // Upload Button
                            Button(action: {
                                showFilePicker = true
                            }) {
                                HStack {
                                    Image(systemName: "arrow.up.doc.fill")
                                        .font(.system(size: 20))
                                    Text("Upload Audio File")
                                        .fontWeight(.semibold)
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 30)
                                .padding(.vertical, 15)
                                .background(
                                    LinearGradient(
                                        gradient: Gradient(colors: [.green, .teal]),
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .cornerRadius(12)
                            }
                            .disabled(isProcessing)
                            .sheet(isPresented: $showFilePicker) {
                                AudioFilePicker(audioURL: $recordedAudioURL)
                            }

                            // Extract Button (only show if audio is recorded/uploaded)
                            if recordedAudioURL != nil && !isProcessing {
                                Button(action: {
                                    extractRule()
                                }) {
                                    HStack {
                                        Image(systemName: "brain.head.profile")
                                            .font(.system(size: 20))
                                        Text("Extract Rule")
                                            .fontWeight(.bold)
                                    }
                                    .foregroundColor(.black)
                                    .padding(.horizontal, 40)
                                    .padding(.vertical, 18)
                                    .background(Color.white)
                                    .cornerRadius(12)
                                    .shadow(color: .white.opacity(0.3), radius: 10)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }

                    // Result Section
                    if showResult, let result = extractionResult {
                        ResultView(result: result, onReset: resetView)
                            .transition(.opacity)
                    }

                    // Error Message
                    if let error = errorMessage {
                        ErrorBanner(message: error)
                    }

                    Spacer()
                }
            }
        }
    }

    // MARK: - Recording Functions

    func startRecording() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord, mode: .default)
            try audioSession.setActive(true)

            let docPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let audioFilename = docPath.appendingPathComponent("dad_os_rule_\(Int(Date().timeIntervalSince1970)).m4a")

            let settings = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]

            audioRecorder = try AVAudioRecorder(url: audioFilename, settings: settings)
            audioRecorder?.record()

            withAnimation {
                isRecording = true
                pulseAnimation = true
            }

            print("🎙️ Recording started: \(audioFilename)")

        } catch {
            errorMessage = "Failed to start recording: \(error.localizedDescription)"
        }
    }

    func stopRecording() {
        audioRecorder?.stop()

        if let url = audioRecorder?.url {
            recordedAudioURL = url
            print("✅ Recording saved: \(url)")
        }

        audioRecorder = nil

        withAnimation {
            isRecording = false
            pulseAnimation = false
        }
    }

    // MARK: - Rule Extraction

    func extractRule() {
        guard let audioURL = recordedAudioURL else {
            errorMessage = "No audio file selected"
            return
        }

        isProcessing = true
        errorMessage = nil
        processingStage = "Uploading audio..."

        // Read audio file
        guard let audioData = try? Data(contentsOf: audioURL) else {
            errorMessage = "Failed to read audio file"
            isProcessing = false
            return
        }

        // Detect format from file extension
        let audioFormat = audioURL.pathExtension.lowercased()

        // Convert to base64
        let audioBase64 = audioData.base64EncodedString()

        // Call backend
        AgentManager.shared.extractDadOsRule(audioData: audioBase64, audioFormat: audioFormat) { [self] response in
            DispatchQueue.main.async {
                self.isProcessing = false

                if let data = response.data(using: .utf8),
                   let result = try? JSONDecoder().decode(RuleExtractionResponse.self, from: data) {

                    if result.success {
                        self.extractionResult = result
                        withAnimation {
                            self.showResult = true
                        }
                    } else {
                        self.errorMessage = "Error at \(result.stage ?? "unknown"): \(result.error ?? "Unknown error")"
                    }
                } else {
                    self.errorMessage = "Failed to parse response"
                }
            }
        }
    }

    func resetView() {
        withAnimation {
            showResult = false
            recordedAudioURL = nil
            extractionResult = nil
            errorMessage = nil
        }
    }
}

// MARK: - Supporting Views

struct ProcessingIndicator: View {
    let stage: String
    @State private var rotation: Double = 0

    var body: some View {
        VStack(spacing: 15) {
            Circle()
                .trim(from: 0, to: 0.7)
                .stroke(
                    LinearGradient(
                        gradient: Gradient(colors: [.blue, .purple]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .frame(width: 40, height: 40)
                .rotationEffect(.degrees(rotation))
                .onAppear {
                    withAnimation(Animation.linear(duration: 1).repeatForever(autoreverses: false)) {
                        rotation = 360
                    }
                }

            Text(stage)
                .font(.caption)
                .foregroundColor(.white)
        }
        .padding()
    }
}

struct ResultView: View {
    let result: RuleExtractionResponse
    let onReset: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Success header
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 30))
                    .foregroundColor(.green)
                Text("Rule Extracted Successfully")
                    .font(.headline)
                    .foregroundColor(.white)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.green.opacity(0.2))
            .cornerRadius(10)

            // Transcript
            if let transcript = result.transcript {
                VStack(alignment: .leading, spacing: 8) {
                    Text("TRANSCRIPT")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.gray)

                    Text(transcript)
                        .font(.body)
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(8)
                }
            }

            // Extracted Rule
            if let rule = result.extracted_rule {
                VStack(alignment: .leading, spacing: 8) {
                    Text("EXTRACTED RULE")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.gray)

                    VStack(alignment: .leading, spacing: 12) {
                        // Trigger Conditions
                        RuleSection(
                            title: "Trigger Conditions",
                            icon: "bolt.fill",
                            color: .yellow,
                            content: formatDictionary(rule.trigger_conditions)
                        )

                        // Action Vetoes
                        RuleSection(
                            title: "Forbidden Actions",
                            icon: "xmark.circle.fill",
                            color: .red,
                            content: rule.action_vetoes.joined(separator: "\n")
                        )

                        // Action Forces
                        RuleSection(
                            title: "Required Actions",
                            icon: "checkmark.circle.fill",
                            color: .green,
                            content: rule.action_forces.joined(separator: "\n")
                        )

                        // Rationale
                        RuleSection(
                            title: "Coach's Rationale",
                            icon: "quote.bubble.fill",
                            color: .blue,
                            content: rule.veteran_rationale
                        )
                    }
                    .padding()
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(10)
                }
            }

            // Rule ID
            if let ruleId = result.rule_id {
                Text("Rule ID: \(ruleId)")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .padding(.horizontal)
            }

            // Reset Button
            Button(action: onReset) {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text("Extract Another Rule")
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .cornerRadius(10)
            }
            .padding(.top, 10)
        }
        .padding()
    }

    func formatDictionary(_ dict: [String: AnyCodable]) -> String {
        dict.map { "\($0.key): \($0.value.value)" }.joined(separator: "\n")
    }
}

struct RuleSection: View {
    let title: String
    let icon: String
    let color: Color
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(title)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(color)
            }

            Text(content.isEmpty ? "None" : content)
                .font(.body)
                .foregroundColor(.white)
        }
    }
}

struct ErrorBanner: View {
    let message: String

    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text(message)
                .font(.caption)
                .foregroundColor(.white)
        }
        .padding()
        .background(Color.orange.opacity(0.2))
        .cornerRadius(10)
        .padding(.horizontal)
    }
}

// MARK: - File Picker

struct AudioFilePicker: UIViewControllerRepresentable {
    @Binding var audioURL: URL?
    @Environment(\.presentationMode) var presentationMode

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [
            UTType.audio,
            UTType(filenameExtension: "m4a")!,
            UTType(filenameExtension: "mp3")!,
            UTType(filenameExtension: "wav")!
        ])
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: AudioFilePicker

        init(_ parent: AudioFilePicker) {
            self.parent = parent
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }

            // Request access to security-scoped resource (required for File Providers)
            guard url.startAccessingSecurityScopedResource() else {
                print("❌ Failed to access security-scoped resource")
                parent.presentationMode.wrappedValue.dismiss()
                return
            }

            defer {
                // Always stop accessing when done
                url.stopAccessingSecurityScopedResource()
            }

            // Copy to app's documents directory
            let docPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let destURL = docPath.appendingPathComponent("uploaded_\(url.lastPathComponent)")

            do {
                if FileManager.default.fileExists(atPath: destURL.path) {
                    try FileManager.default.removeItem(at: destURL)
                }
                try FileManager.default.copyItem(at: url, to: destURL)
                parent.audioURL = destURL
                print("✅ Audio file uploaded: \(destURL)")
            } catch {
                print("❌ Error copying file: \(error)")
            }

            parent.presentationMode.wrappedValue.dismiss()
        }
    }
}
