import SwiftUI
import HealthKit

// Simple Message Model for UI
struct ChatMessageModel: Identifiable, Equatable {
    let id = UUID()
    let role: String // "user" or "model"
    let text: String
}

struct CoachChatView: View {
    let workout: HKWorkout
    let initialAnalysis: String
    
    @State private var messages: [ChatMessageModel] = []
    @State private var inputText: String = ""
    @State private var isTyping: Bool = false
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            VStack {
                // MARK: - Chat List
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            // Initial Greeting (System/Coach)
                            ChatBubble(text: initialAnalysis, isUser: false)
                                .id("initial")
                            
                            ForEach(messages) { msg in
                                ChatBubble(text: msg.text, isUser: msg.role == "user")
                                    .id(msg.id)
                            }
                            
                            if isTyping {
                                HStack {
                                    Text("Coach is typing...")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                        .padding(.leading)
                                    Spacer()
                                }
                                .id("typing")
                            }
                        }
                        .padding()
                    }
                    .onChange(of: messages) { _ in
                        withAnimation {
                            proxy.scrollTo(messages.last?.id, anchor: .bottom)
                        }
                    }
                    .onChange(of: isTyping) { typing in
                        if typing {
                            withAnimation {
                                proxy.scrollTo("typing", anchor: .bottom)
                            }
                        }
                    }
                }
                
                // MARK: - Input Area
                HStack {
                    TextField("Ask the Coach...", text: $inputText)
                        .padding(10)
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(20)
                        .submitLabel(.send)
                        .onSubmit {
                            sendMessage()
                        }
                    
                    Button(action: sendMessage) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 30))
                            .foregroundColor(.blue)
                    }
                    .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding()
                .background(Color(UIColor.systemBackground))
            }
            .navigationTitle("Coach Chat 💬")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            // Optional: Add a "system" message to history if needed by backend, 
            // but for UI, we just show the initial analysis bubble.
        }
    }
    
    func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        
        let userMsg = ChatMessageModel(role: "user", text: text)
        
        // Snapshot history for background processing
        let currentMessages = messages
        
        // UI Update (Immediate)
        messages.append(userMsg)
        inputText = ""
        isTyping = true
        
        // Offload O(N) history building to background
        DispatchQueue.global(qos: .userInitiated).async {
            var historyPayload: [[String: String]] = [
                ["role": "model", "text": self.initialAnalysis]
            ]
            
            for m in currentMessages {
                historyPayload.append(["role": m.role, "text": m.text])
            }
            historyPayload.append(["role": "user", "text": text])
            
            // Call Agent
            AgentManager.shared.chatWithCoach(workout: self.workout, history: historyPayload) { response in
                DispatchQueue.main.async { // Back to Main for UI update
                    let coachMsg = ChatMessageModel(role: "model", text: response)
                    self.messages.append(coachMsg)
                    self.isTyping = false
                }
            }
        }
    }
}

// MARK: - Subviews
struct ChatBubble: View {
    let text: String
    let isUser: Bool
    
    var body: some View {
        HStack(alignment: .bottom) {
            if isUser { Spacer() }
            
            Text(text)
                .padding()
                .background(isUser ? Color.blue : Color(UIColor.secondarySystemBackground))
                .foregroundColor(isUser ? .white : .primary)
                .cornerRadius(16)
                // Corner radius adjustment for bubble effect
                .clipShape(
                    RoundedRectangle(cornerRadius: 16)
                )
                .frame(maxWidth: 280, alignment: isUser ? .trailing : .leading)
            
            if !isUser { Spacer() }
        }
    }
}
