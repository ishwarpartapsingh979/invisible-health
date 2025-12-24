//
//  ChatView.swift
//  Invisible_Health
//
//  Created by Ishwar Partap Singh on 23/12/25.
//

import SwiftUI
struct ChatView: View {
    @State private var message: String = ""
    
    var body: some View {
        VStack {
            // Chat History Placeholder
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Hello! I am your Nutrition AI. What did you eat?")
                            .padding()
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(12)
                            .foregroundColor(.white)
                        Spacer()
                    }
                    
                    HStack {
                        Spacer()
                        Text("I had a salmon bowl.")
                            .padding()
                            .background(Color.orange)
                            .cornerRadius(12)
                            .foregroundColor(.white)
                    }
                }
                .padding()
            }
            
            Spacer()
            
            // Input Area
            HStack {
                TextField("Ask something...", text: $message)
                    .padding(12)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(20)
                    .foregroundColor(.white)
                
                Button(action: {
                    message = ""
                }) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title)
                        .foregroundColor(.orange)
                }
            }
            .padding()
        }
        .background(Color.black)
    }
}
