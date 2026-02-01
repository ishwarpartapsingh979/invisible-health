import SwiftUI

struct SummaryView: View {
    @State private var analysis: String = "Gathering data for 10 PM Report..."
    @State private var vo2: Double?
    @State private var hrv: Double?
    @State private var rhr: Double?
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                // Header
                Text("Holistic Summary")
                    .font(.largeTitle)
                    .bold()
                    .foregroundColor(.white)
                    .padding(.top, 40)
                    .padding(.horizontal)
                
                // MARK: - CNS Readiness (The Governor)
                VStack(alignment: .leading, spacing: 15) {
                    Text("🔋 CNS Readiness")
                        .font(.headline)
                        .foregroundColor(.gray)
                    
                    HStack(spacing: 15) {
                        ReadinessCard(title: "HRV (SDNN)", value: hrv != nil ? String(format: "%.0f ms", hrv!) : "--", status: "Neutral")
                        ReadinessCard(title: "Resting HR", value: rhr != nil ? String(format: "%.0f bpm", rhr!) : "--", status: "Good")
                    }
                    
                    if let v = vo2 {
                        Text("VO₂ Max Trend: \(String(format: "%.1f", v)) ml/kg/min")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
                .padding(.horizontal)
                
                // MARK: - Daily Briefing (Fuel vs Engine)
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "brain.head.profile")
                            .foregroundColor(.purple)
                        Text("The Coach Report")
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                    
                    Text(analysis)
                        .font(.body)
                        .foregroundColor(.white.opacity(0.9))
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(12)
                    
                    Button(action: { generateReport() }) {
                        Text("Generate Now")
                            .font(.caption)
                            .fontWeight(.bold)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 16)
                            .background(Color.purple)
                            .foregroundColor(.white)
                            .cornerRadius(20)
                    }
                    .padding(.top, 5)
                }
                .padding()
                .background(Color(UIColor.secondarySystemBackground).opacity(0.1))
                .cornerRadius(20)
                .padding(.horizontal)
                
                Spacer()
            }
        }
        .background(Color.black.edgesIgnoringSafeArea(.all))
        .onAppear {
            HealthManager.shared.fetchEliteBiometrics { v, h, r in
                self.vo2 = v
                self.hrv = h
                self.rhr = r
            }
        }
    }
    
    func generateReport() {
        self.analysis = "Analyzing your Food (Fuel) vs Workouts (Engine)...\n\n• Calories In: --\n• Active Burn: --\n• Net Status: Calculating..."
        
        AgentManager.shared.generateDailyReport { report in
             self.analysis = report
        }
    }
}

struct ReadinessCard: View {
    let title: String
    let value: String
    let status: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.gray)
            
            Text(value)
                .font(.title2)
                .bold()
                .foregroundColor(.white)
            
            Text(status)
                .font(.caption2)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.green.opacity(0.2))
                .foregroundColor(.green)
                .cornerRadius(8)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.1))
        .cornerRadius(12)
    }
}
