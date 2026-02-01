//
//  DataFeedView.swift
//  Invisible_Health
//
//  Created by Ishwar Partap Singh on 23/12/25.
//

import SwiftUI

struct LogSection: Identifiable {
    let id = UUID()
    let date: Date
    let logs: [AgentManager.NutritionLog]
}

struct DataFeedView: View {
    // Real Data
    @State private var logs: [AgentManager.NutritionLog] = []
    @State private var editingLog: AgentManager.NutritionLog? // For Sheet
    
    // Grouping Helper
    var sections: [LogSection] {
        let grouped = Dictionary(grouping: logs) { (log) -> Date in
            // Parse ISO date string to Date object
            let formatter = ISO8601DateFormatter()
             // Ensure we parse the date part only for grouping, or strip time
             if let date = formatter.date(from: log.created_at) {
                 return Calendar.current.startOfDay(for: date)
             }
             return Date.distantPast
        }
        return grouped.sorted { $0.key > $1.key }.map { LogSection(date: $0.key, logs: $0.value) }
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("Your Log")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .padding()
            
            ScrollView {
                LazyVStack(spacing: 20, pinnedViews: [.sectionHeaders]) {
                    if logs.isEmpty {
                        Text("No logs yet. Try logging some food!")
                            .foregroundColor(.gray)
                            .padding(.top, 40)
                    } else {
                        ForEach(sections) { section in
                            Section(header: headerView(for: section.date)) {
                                ForEach(section.logs) { log in
                                    logRow(log)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
        .background(Color.black)
        .sheet(item: $editingLog) { log in
            EditLogView(log: log, onSave: { updatedLog in
                 // Optimistic UI Update (or re-fetch)
                 if let index = logs.firstIndex(where: { $0.id == updatedLog.id }) {
                     logs[index] = updatedLog
                 }
            })
        }
        .onAppear {
            // Fetch Real Data
            AgentManager.shared.fetchLogs { fetchedLogs in
                self.logs = fetchedLogs
            }
        }
    }
    
    // Header View
    func headerView(for date: Date) -> some View {
        HStack {
            Text(dateLabel(for: date).uppercased())
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.gray)
                .tracking(1)
            Spacer()
        }
        .padding(.vertical, 8)
        .background(Color.black) // Sticky header needs background
    }
    
    func dateLabel(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: date)
    }
    
    // Extracted Row
    func logRow(_ log: AgentManager.NutritionLog) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                // Row 1: Name & Calories
                HStack {
                    Text(log.food_name)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                    Spacer()
                    if let cals = log.calories {
                        Text("\(Int(cals)) kcal")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
                
                // Row 2: Macros (Optional)
                if let p = log.protein, let c = log.carbs, let f = log.fats {
                    Text("P: \(Int(p))g • C: \(Int(c))g • F: \(Int(f))g")
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
                
                // Row 3: AI Commentary (The "Message")
                if let msg = log.message {
                    Text(msg)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                        .italic()
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
            }
            
            // Edit Button
            Button(action: {
                self.editingLog = log
            }) {
                Image(systemName: "pencil.circle.fill")
                    .font(.title3)
                    .foregroundColor(.gray)
            }
            .padding(.leading, 8)
        }
        .padding()
        .background(Color.white.opacity(0.1))
        .cornerRadius(12)
    }
}
