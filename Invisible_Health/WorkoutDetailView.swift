import SwiftUI
import HealthKit

struct WorkoutDetailView: View {
    let workout: HKWorkout
    @State private var oscillation: Double?
    @State private var gct: Double?
    @State private var power: Double?
    
    @State private var analysis: String = "Tap to Analyze"
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                
                // MARK: - Header
                VStack(alignment: .leading) {
                    Text("Performance Lab")
                        .font(.largeTitle)
                        .bold()
                    Text(workout.startDate.formatted())
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
                .padding(.horizontal)
                
                // MARK: - AI Coach (Analysis)
                VStack(alignment: .leading, spacing: 10) {
                    Text("🤖 Coach's Insight")
                        .font(.headline)
                    
                    Text(analysis)
                        .font(.body)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(10)
                        
                    Button("Analyze with Agent") {
                         AgentManager.shared.analyzeLastWorkout { result in
                             self.analysis = result
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
                
                // MARK: - 1. Biomechanics
                SectionHeader(title: "Running Biomechanics", icon: "figure.run")
                
                HStack(spacing: 15) {
                    MetricCard(title: "Vert. Oscillation", value: oscillation != nil ? String(format: "%.1f cm", oscillation!) : "--", target: "< 8 cm")
                    MetricCard(title: "GCT", value: gct != nil ? String(format: "%.0f ms", gct!) : "--", target: "< 200 ms")
                }
                .padding(.horizontal)
                
                 HStack(spacing: 15) {
                    MetricCard(title: "Power", value: power != nil ? String(format: "%.0f W", power!) : "--", target: "High Output")
                    MetricCard(title: "Cadence", value: "--", target: "170+ spm") // Placeholder
                 }
                 .padding(.horizontal)
                
                // MARK: - 2. Cardio Engine
                SectionHeader(title: "Cardio Engine", icon: "heart.fill")
                
                HStack(spacing: 15) {
                    MetricCard(title: "Avg Heart Rate", value: "-- bpm", target: "Zone 2")
                    MetricCard(title: "HR Recovery", value: "-- bpm", target: "> 20 bpm")
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .padding(.top)
        }
        .onAppear {
            HealthManager.shared.fetchWorkoutMetrics(workout: workout) { osc, gct, pwr in
                self.oscillation = osc
                self.gct = gct
                self.power = pwr
            }
        }
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
