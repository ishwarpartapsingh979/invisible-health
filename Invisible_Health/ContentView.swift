import SwiftUI
import AVFoundation
struct ContentView: View {
    @EnvironmentObject var notificationManager: NotificationManager
    
    // UI State
    @State private var showTextInput: Bool = false
    @State private var textInput: String = ""
    @State private var showSOS: Bool = false // Phase 5
    @State private var pulseEvaluate: Bool = false
    
    // Tab Selection (0: Log/Home, 1: Chat, 2: Data)
    @State private var selectedTab: Int = 0
    
    var body: some View {
        ZStack {
            // Background
            Color.black.edgesIgnoringSafeArea(.all)
            
            VStack {
                // MARK: - Header
                if selectedTab == 0 {
                    Text("SYSTEM READY")
                        .font(.caption)
                        .fontWeight(.medium)
                        .tracking(2)
                        .foregroundColor(.gray)
                        .padding(.top, 60)
                } else {
                    Spacer().frame(height: 60)
                }
                
                Spacer()
                
                // MARK: - Main Content Switcher
                switch selectedTab {
                case 1:
                    ChatView()
                case 2:
                    DataFeedView()
                default:
                    // Tab 0: Home / Mic Screen
                    micView
                }
                
                Spacer()
                
                // MARK: - Bottom Tab Bar
                HStack(spacing: 30) {
                    TabButton(icon: "keyboard", text: "LOG", isSelected: selectedTab == 0) {
                        if selectedTab == 0 {
                            // If already on Log tab, toggle Text Input
                            withAnimation { showTextInput = true }
                        } else {
                            selectedTab = 0
                        }
                    }
                    TabButton(icon: "message", text: "CHAT", isSelected: selectedTab == 1) { selectedTab = 1 }
                    TabButton(icon: "chart.bar", text: "DATA", isSelected: selectedTab == 2) { selectedTab = 2 }
                    
                    // SOS Button
                    TabButton(icon: "exclamationmark.circle.fill", text: "SOS", isSelected: false) {
                        showSOS = true
                    }
                }
                .padding(.bottom, 40)
            }
            
            // MARK: - Text Input Overlay
            if showTextInput {
                Color.black.opacity(0.8).edgesIgnoringSafeArea(.all)
                    .onTapGesture { showTextInput = false }
                
                VStack {
                    Text("Log Food")
                        .font(.title2)
                        .foregroundColor(.white)
                    
                    TextField("Ex: 2 eggs and toast", text: $textInput)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .padding()
                    
                    Button("Log It") {
                        print("Logging: \(textInput)")
                        showTextInput = false
                        textInput = ""
                        // Trigger Smart Notification Simulation
                        NotificationManager.shared.simulateBackendAnalysis()
                    }
                    .padding()
                    .background(Color.orange)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .frame(width: 300)
                .padding()
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(20)
            }
        }
        // Handle Logic when App is Opened via "plus" button (URL Scheme)
        .onOpenURL { url in
            print("🔗 Deep Link: \(url.absoluteString)")
            if url.absoluteString.contains("chat") {
                selectedTab = 1
            } else if url.absoluteString.contains("data") {
                selectedTab = 2
            } else if url.absoluteString.contains("sos") {
                showSOS = true
            } else if url.absoluteString.contains("open") {
                // Just open, maybe default to Home
            }
        }
        .sheet(isPresented: $showSOS) {
            SOSView()
        }
    }
    
    // State for Media Pickers
    @State private var showCamera = false
    @State private var showGallery = false
    @State private var selectedImage: UIImage?
    
    // State for Recording
    @State private var isRecording = false
    @State private var audioRecorder: AVAudioRecorder?
    
    // Extracted Mic View with Functional Buttons
    var micView: some View {
        HStack(spacing: 40) {
            // Gallery Button (Left)
            Button(action: {
                print("Gallery Tapped")
                showGallery = true
            }) {
                Circle()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 60, height: 60)
                    .overlay(
                        Image(systemName: "photo")
                            .font(.system(size: 24))
                            .foregroundColor(.gray)
                    )
            }
            .sheet(isPresented: $showGallery) {
                ImagePicker(sourceType: .photoLibrary, selectedImage: $selectedImage)
            }
            
            // Main Mic Button (Center)
            ZStack {
                // Pulse Animation (Only when recording)
                if isRecording {
                    Circle()
                        .fill(RadialGradient(
                            gradient: Gradient(colors: [.red.opacity(0.6), .clear]),
                            center: .center,
                            startRadius: 50,
                            endRadius: 150
                        ))
                        .frame(width: 250, height: 250)
                        .scaleEffect(pulseEvaluate ? 1.2 : 0.8)
                        .opacity(pulseEvaluate ? 0.8 : 0.0)
                        .animation(Animation.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulseEvaluate)
                        .onAppear { pulseEvaluate = true }
                }
                
                // Main Button Info
                Circle()
                    .fill(LinearGradient(
                        gradient: Gradient(colors: isRecording ? [.red, .pink] : [.orange, .red]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 140, height: 140)
                    .shadow(color: isRecording ? .red.opacity(0.6) : .orange.opacity(0.5), radius: 20, x: 0, y: 10)
                    .overlay(
                        VStack(spacing: 8) {
                            Image(systemName: isRecording ? "square.fill" : "mic.fill")
                                .font(.system(size: isRecording ? 40 : 50))
                                .foregroundColor(.white)
                            
                            if isRecording {
                                Text("REC")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                    .transition(.opacity)
                            }
                        }
                    )
            }
            .onTapGesture {
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
                
                if isRecording {
                    stopRecording()
                } else {
                    startRecording()
                }
            }
            
            // Camera Button (Right)
            Button(action: {
                 print("Camera Tapped")
                 showCamera = true
            }) {
                Circle()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 60, height: 60)
                    .overlay(
                        Image(systemName: "camera")
                            .font(.system(size: 24))
                            .foregroundColor(.gray)
                    )
            }
            .sheet(isPresented: $showCamera) {
                ImagePicker(sourceType: .camera, selectedImage: $selectedImage)
            }
        }
    }
    
    // MARK: - Audio Recording Logic
    func startRecording() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord, mode: .default)
            try audioSession.setActive(true)
            
            let docPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let audioFilename = docPath.appendingPathComponent("nutrition_log.m4a")
            
            let settings = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 12000,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            
            audioRecorder = try AVAudioRecorder(url: audioFilename, settings: settings)
            audioRecorder?.record()
            
            withAnimation {
                isRecording = true
            }
            print("🎙️ REAL Recording Started at: \(audioFilename.absoluteString)")
            
        } catch {
            print("❌ Failed to start recording: \(error.localizedDescription)")
        }
    }
    
    func stopRecording() {
        audioRecorder?.stop()
        audioRecorder = nil
        
        withAnimation {
            isRecording = false
        }
        print("🛑 REAL Recording Stopped. Audio saved.")
        
        // Trigger Analysis
        NotificationManager.shared.simulateBackendAnalysis()
    }
}
// Simple Image Picker Wrapper
struct ImagePicker: UIViewControllerRepresentable {
    var sourceType: UIImagePickerController.SourceType = .photoLibrary
    @Binding var selectedImage: UIImage?
    @Environment(\.presentationMode) private var presentationMode
    func makeUIViewController(context: UIViewControllerRepresentableContext<ImagePicker>) -> UIImagePickerController {
        let imagePicker = UIImagePickerController()
        imagePicker.allowsEditing = false
        imagePicker.sourceType = sourceType
        imagePicker.delegate = context.coordinator
        return imagePicker
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: UIViewControllerRepresentableContext<ImagePicker>) {}
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        var parent: ImagePicker
        init(_ parent: ImagePicker) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[UIImagePickerController.InfoKey.originalImage] as? UIImage {
                parent.selectedImage = image
                // Simulate Analysis when image is picked
                NotificationManager.shared.simulateBackendAnalysis()
            }
            parent.presentationMode.wrappedValue.dismiss()
        }
    }
}
// Helper for Tab Buttons
struct TabButton: View {
    let icon: String
    let text: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundColor(isSelected ? .white : .gray)
                    .padding(12)
                    .background(isSelected ? Color.white.opacity(0.1) : Color.clear)
                    .cornerRadius(12)
                
                Text(text)
                    .font(.caption2)
                    .fontWeight(.bold)
                    .tracking(1)
                    .foregroundColor(isSelected ? .white : .gray)
            }
        }
    }
}

