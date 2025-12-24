//
//  SOSView.swift
//  Invisible_Health
//
//  Created by Ishwar Partap Singh on 23/12/25.
//

import SwiftUI
struct SOSView: View {
    @Environment(\.presentationMode) var presentationMode
    
    // Placeholder Data for Cravings Fighters
    // In the future, this will be fetched from Gemini
    let strategies = [
        CravingsStrategy(icon: "lungs.fill", title: "5-Minute Box Breathing", description: "Inhale 4s, Hold 4s, Exhale 4s, Hold 4s.", color: .blue),
        CravingsStrategy(icon: "drop.fill", title: "Drink a Glass of Water", description: "Sometimes thirst is confused for hunger.", color: .cyan),
        CravingsStrategy(icon: "figure.walk", title: "Take a Brisk Walk", description: "Change your environment to reset your mind.", color: .green),
        CravingsStrategy(icon: "phone.fill", title: "Call a Friend", description: "Distraction is the best cure.", color: .orange)
    ]
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(UIColor.systemGroupedBackground).edgesIgnoringSafeArea(.all)
                
                VStack(spacing: 20) {
                    // Header
                    VStack(spacing: 10) {
                        Image(systemName: "exclamationmark.shield.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.red)
                            .padding(.top, 40)
                        
                        Text("Cravings SOS")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                        
                        Text("You are stronger than this moment.\nChoose a strategy to reset.")
                            .font(.body)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                    }
                    .padding(.bottom, 20)
                    
                    // List of Strategies
                    ScrollView {
                        VStack(spacing: 15) {
                            ForEach(strategies) { strategy in
                                StrategyCard(strategy: strategy)
                            }
                            
                            // AI Placeholder
                            HStack {
                                Image(systemName: "sparkles")
                                Text("More AI Suggestions coming soon...")
                                    .font(.caption)
                                    .italic()
                            }
                            .foregroundColor(.gray)
                            .padding(.top, 20)
                        }
                        .padding(.horizontal)
                    }
                }
            }
            .navigationBarItems(trailing: Button("Close") {
                presentationMode.wrappedValue.dismiss()
            })
        }
    }
}
struct CravingsStrategy: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let description: String
    let color: Color
}
struct StrategyCard: View {
    let strategy: CravingsStrategy
    
    var body: some View {
        HStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(strategy.color.opacity(0.15))
                    .frame(width: 60, height: 60)
                
                Image(systemName: strategy.icon)
                    .font(.title2)
                    .foregroundColor(strategy.color)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(strategy.title)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text(strategy.description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .foregroundColor(.gray.opacity(0.5))
        }
        .padding()
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}
