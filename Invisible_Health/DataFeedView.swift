//
//  DataFeedView.swift
//  Invisible_Health
//
//  Created by Ishwar Partap Singh on 23/12/25.
//

import SwiftUI

struct DataFeedView: View {
    // Real Data
    @State private var logs: [AgentManager.NutritionLog] = []
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("Your Log")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .padding()
            
            ScrollView {
                VStack(spacing: 16) {
                    if logs.isEmpty {
                        Text("No logs yet. Try logging some food!")
                            .foregroundColor(.gray)
                            .padding(.top, 40)
                    } else {
                        ForEach(logs) { log in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(log.food_name)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.white)
                                    Text("\(log.calories) kcal") // Simplified format
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                                Spacer()
                                Text(log.formattedDate)
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                            }
                            .padding()
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(12)
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
        .background(Color.black)
        .onAppear {
            // Fetch Real Data
            AgentManager.shared.fetchLogs { fetchedLogs in
                self.logs = fetchedLogs
            }
        }
    }
}
