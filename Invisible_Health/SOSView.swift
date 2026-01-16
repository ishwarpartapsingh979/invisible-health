//
//  SOSView.swift
//  Invisible_Health
//
//  Created by Ishwar Partap Singh on 23/12/25.
//

import SwiftUI

struct SOSView: View {
    @Environment(\.presentationMode) var presentationMode
    
    // Real Data
    @State private var strategies: [AgentManager.AgentSOSStrategy] = []
    @State private var isLoading = true
    
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
                    if isLoading {
                        ProgressView("Asking AI for help...")
                            .padding()
                    } else {
                        ScrollView {
                            VStack(spacing: 15) {
                                ForEach(strategies) { strategy in
                                    StrategyCard(strategy: strategy)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }
            }
            .navigationBarItems(trailing: Button("Close") {
                presentationMode.wrappedValue.dismiss()
            })
        }
        .onAppear {
            AgentManager.shared.fetchSOSStrategies { fetchedStrategies in
                self.strategies = fetchedStrategies
                self.isLoading = false
            }
        }
    }
}

// Helper View
struct StrategyCard: View {
    let strategy: AgentManager.AgentSOSStrategy
    
    var body: some View {
        HStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(color(from: strategy.color).opacity(0.15))
                    .frame(width: 60, height: 60)
                
                Image(systemName: strategy.icon)
                    .font(.title2)
                    .foregroundColor(color(from: strategy.color))
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
    
    func color(from name: String) -> Color {
        switch name {
        case "blue": return .blue
        case "red": return .red
        case "green": return .green
        case "orange": return .orange
        case "purple": return .purple
        case "cyan": return .cyan
        default: return .gray
        }
    }
}
