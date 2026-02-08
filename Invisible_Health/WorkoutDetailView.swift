import SwiftUI
import HealthKit

struct MetricItem: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    let target: String
}

struct MetricSection: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
    let items: [MetricItem]
}

struct WorkoutDetailView: View {
    let workout: HKWorkout
    @State private var metrics: [String: Any] = [:]
    @State private var analysis: String = "Tap to Analyze"
    @State private var isLoading: Bool = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                
                // MARK: - Header
                HStack {
                    VStack(alignment: .leading) {
                        Text(workout.workoutActivityType.name)
                            .font(.largeTitle)
                            .bold()
                        Text(workout.startDate.formatted(date: .abbreviated, time: .shortened))
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                    Spacer()
                    
                    // Share / Send to Coach
                    if #available(iOS 16.0, *) {
                        ShareLink(item: generateCoachReport()) {
                            Label("Send to Coach", systemImage: "square.and.arrow.up")
                                .font(.caption)
                                .padding(8)
                                .background(Color.orange.opacity(0.1))
                                .foregroundColor(.orange)
                                .cornerRadius(8)
                        }
                    } else {
                        // Fallback for older iOS (Print or Alert)
                        Button(action: { print(generateCoachReport()) }) {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundColor(.gray)
                        }
                    }
                }
                .padding(.horizontal)
                
                // MARK: - AI Coach (Analysis)
                VStack(alignment: .leading, spacing: 10) {
                    Text("🤖 \(getCoachPersona()) Insight")
                        .font(.headline)
                    
                    if isLoading {
                        ProgressView()
                            .padding()
                    } else {
                        Text(analysis)
                            .font(.body)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(10)
                    }
                        
                    Button("Analyze with Agent") {
                         self.isLoading = true
                         AgentManager.shared.analyzeWorkout(workout: self.workout) { result in
                             self.analysis = result
                             self.isLoading = false
                         }
                    }
                    .font(.caption)
                    .padding(8)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .padding()
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(15)
                .padding(.horizontal)
                
                // MARK: - Dynamic Sections
                ForEach(generateSections()) { section in
                    VStack(alignment: .leading) {
                        SectionHeader(title: section.title, icon: section.icon)
                        
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 15) {
                            ForEach(section.items) { item in
                                MetricCard(title: item.title, value: item.value, target: item.target)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                
                Spacer()
            }
            .padding(.top)
        }
        .onAppear {
            HealthManager.shared.fetchComprehensiveWorkoutData(workout: workout) { data in
                self.metrics = data
            }
        }
    }
    
    // MARK: - Logic
    func getCoachPersona() -> String {
        switch workout.workoutActivityType {
        case .soccer: return "Scout"
        case .tableTennis, .tennis: return "Reflex Coach"
        case .cycling: return "Tour Director"
        case .swimming: return "Aquatics Director"
        case .downhillSkiing: return "Alpine Guide"
        default: return "Coach"
        }
    }
    
    func generateCoachReport() -> String {
        let durationMin = Int(workout.duration / 60)
        let cals = metrics["active_calories"] as? Double ?? 0
        
        var report = """
        🏅 \(workout.workoutActivityType.name) Session
        📅 \(workout.startDate.formatted(date: .abbreviated, time: .shortened))
        ⏱ \(durationMin) min | 🔥 \(Int(cals)) kcal
        
        📊 Key Metrics:
        """
        
        // Add Metrics
        let sections = generateSections()
        for section in sections {
            for item in section.items {
                report += "\n- \(item.title): \(item.value)"
            }
        }
        
        report += "\n\n🤖 \(getCoachPersona()) Insight:\n\(analysis)"
        
        return report
    }
    
    func generateSections() -> [MetricSection] {
        var sections: [MetricSection] = []
        
        // 1. Core / Cardio (Universal)
        var cardioItems: [MetricItem] = []
        if let avgHR = metrics["avg_hr"] as? Double {
            cardioItems.append(MetricItem(title: "Avg HR", value: "\(Int(avgHR)) bpm", target: "Zone 2"))
        }
        if let maxHR = metrics["max_hr"] as? Double {
            cardioItems.append(MetricItem(title: "Max HR", value: "\(Int(maxHR)) bpm", target: "Peak"))
        }
        if let cals = metrics["active_calories"] as? Double {
            cardioItems.append(MetricItem(title: "Active Cals", value: "\(Int(cals)) kcal", target: "Burn"))
        }
        if !cardioItems.isEmpty {
            sections.append(MetricSection(title: "Cardio Engine", icon: "heart.fill", items: cardioItems))
        }
        
        // 2. Performance (Sport Specific)
        var perfItems: [MetricItem] = []
        
        // Distance
        if let dist = metrics["distance_meters"] as? Double {
            let km = dist / 1000.0
            perfItems.append(MetricItem(title: "Distance", value: String(format: "%.2f km", km), target: "Volume"))
        }
        // Cadence (Run/Cycle)
        if let cad = metrics["avg_cadence"] as? Double {
            let unit = workout.workoutActivityType == .cycling ? "rpm" : "spm"
            perfItems.append(MetricItem(title: "Cadence", value: "\(Int(cad)) \(unit)", target: "Rhythm"))
        }
        // Power
        if let pwr = metrics["avg_power_watts"] as? Double {
             perfItems.append(MetricItem(title: "Power", value: "\(Int(pwr)) W", target: "Intensity"))
        }
        // Speed
        // if let speed... (not captured yet, but could derive)
        
        if !perfItems.isEmpty {
             sections.append(MetricSection(title: "Performance", icon: "speedometer", items: perfItems))
        }
        
        // 3. Technical / Biomechanics
        var techItems: [MetricItem] = []
        
        // Running Bio
        if let osc = metrics["avg_oscillation_cm"] as? Double {
            techItems.append(MetricItem(title: "Vert. Oscillation", value: String(format: "%.1f cm", osc), target: "< 8 cm"))
        }
        if let gct = metrics["avg_gct_ms"] as? Double {
            techItems.append(MetricItem(title: "GCT", value: "\(Int(gct)) ms", target: "< 200 ms"))
        }
        if let stride = metrics["avg_stride_len"] as? Double {
            techItems.append(MetricItem(title: "Stride Length", value: String(format: "%.2f m", stride), target: "Range"))
        }
        
        // Swimming Bio
        if let strokes = metrics["total_strokes"] as? Double {
            techItems.append(MetricItem(title: "Total Strokes", value: "\(Int(strokes))", target: "Efficiency"))
        }
        
        if !techItems.isEmpty {
            sections.append(MetricSection(title: "Technique", icon: "waveform.path.ecg", items: techItems))
        }
        
        return sections
    }
}

struct SectionHeader: View {
    let title: String
    let icon: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.orange)
            Text(title)
                .font(.headline)
        }
        .padding(.horizontal)
        .padding(.top, 10)
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let target: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundColor(.gray)
            
            Text(value)
                .font(.title2)
                .bold()
            
            Text("Target: \(target)")
                .font(.caption2)
                .foregroundColor(.green)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(UIColor.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
    }
}
