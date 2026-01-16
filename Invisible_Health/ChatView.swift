//
//  ChatView.swift
//  Invisible_Health
//
//  Created by Ishwar Partap Singh on 23/12/25.
//

import SwiftUI
import PhotosUI

struct ChatMessage: Identifiable {
    let id = UUID()
    let text: String
    let isUser: Bool
    let image: UIImage? // Multimodal
}

struct ChatView: View {
    @State private var message: String = ""
    @State private var chatHistory: [ChatMessage] = [
        ChatMessage(text: "Hello! I am your Nutrition AI. What did you eat?", isUser: false, image: nil)
    ]
    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var selectedImage: UIImage? = nil
    
    var body: some View {
        VStack {
            // Chat History
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(chatHistory) { msg in
                            HStack(alignment: .bottom) {
                                if msg.isUser { Spacer() }
                                
                                VStack(alignment: msg.isUser ? .trailing : .leading) {
                                    // Image Bubble
                                    if let img = msg.image {
                                        Image(uiImage: img)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 150, height: 150)
                                            .cornerRadius(12)
                                            .clipped()
                                    }
                                    
                                    // Text Bubble
                                    if !msg.text.isEmpty {
                                        Text(msg.text)
                                            .padding()
                                            .background(msg.isUser ? Color.orange : Color.gray.opacity(0.2))
                                            .cornerRadius(12)
                                            .foregroundColor(.white)
                                    }
                                }
                                
                                if !msg.isUser { Spacer() }
                            }
                            .id(msg.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: chatHistory.count) { _ in
                    if let lastMsg = chatHistory.last {
                        withAnimation {
                            proxy.scrollTo(lastMsg.id, anchor: .bottom)
                        }
                    }
                }
            }
            
            Spacer()
            
            // Input Area
            VStack(spacing: 0) {
                // Image Preview (if attached)
                if let image = selectedImage {
                    HStack {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 60, height: 60)
                            .cornerRadius(8)
                            .clipped()
                            .overlay(
                                Button(action: {
                                    selectedImage = nil
                                    selectedItem = nil
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.red)
                                        .background(Color.white.clipShape(Circle()))
                                }
                                .offset(x: 25, y: -25)
                            )
                        
                        Text("Photo attached")
                            .font(.caption)
                            .foregroundColor(.gray)
                        
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }
                
                HStack {
                    // Photo Picker Button
                    PhotosPicker(selection: $selectedItem, matching: .images) {
                        Image(systemName: "photo")
                            .font(.title2)
                            .foregroundColor(.gray)
                    }
                    .onChange(of: selectedItem) { newItem in
                        Task {
                            if let data = try? await newItem?.loadTransferable(type: Data.self),
                               let uiImage = UIImage(data: data) {
                                selectedImage = uiImage
                            }
                        }
                    }
                    
                    TextField("Ask or Log...", text: $message)
                        .padding(12)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(20)
                        .foregroundColor(.white)
                    
                    Button(action: sendMessage) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title)
                            .foregroundColor((message.isEmpty && selectedImage == nil) ? .gray : .orange)
                    }
                    .disabled(message.isEmpty && selectedImage == nil)
                }
                .padding()
            }
        }
        .background(Color.black)
    }
    
    func sendMessage() {
        let textToSend = message
        let imageToSend = selectedImage
        
        // 1. Add User Message to UI
        let userMsg = ChatMessage(text: textToSend, isUser: true, image: imageToSend)
        chatHistory.append(userMsg)
        
        // Clear Input
        message = ""
        selectedImage = nil
        selectedItem = nil
        
        // 2. Call the Real Brain
        AgentManager.shared.sendMultimodalInput(text: textToSend, image: imageToSend) { responseText in
            DispatchQueue.main.async {
                let reply = ChatMessage(text: responseText, isUser: false, image: nil)
                chatHistory.append(reply)
            }
        }
    }
}
