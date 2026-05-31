//
//  GeminiWorkoutRecommendationView.swift
//  Invisible_Health
//
//  Calls backend action=workout_recommendation_unified which fuses Apple Health
//  + Whoop signals via Gemini Pro and returns a structured WorkoutRecommendation.
//

import SwiftUI

struct GeminiWorkoutRecommendationView: View {
    @StateObject private var agent = AgentManager.shared

    @State private var rec: AgentManager.WorkoutRecommendation?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var lastUpdated: Date?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                if isLoading && rec == nil {
                    loadingPlaceholder
                } else if let rec = rec {
                    recommendationCard(rec)
                    signalsSection(rec)
                    logicSection(rec)
                } else if let error = errorMessage {
                    errorView(error)
                } else {
                    emptyState
                }

                Spacer(minLength: 40)
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
        }
        .background(Color.black.edgesIgnoringSafeArea(.all))
        .onAppear {
            if rec == nil { refresh() }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("WORKOUT")
                .font(.caption)
                .fontWeight(.semibold)
                .tracking(2)
                .foregroundColor(.gray)
            HStack(alignment: .firstTextBaseline) {
                Text("Recommended")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                Spacer()
                Button(action: refresh) {
                    Image(systemName: isLoading ? "hourglass" : "arrow.clockwise")
                        .font(.title3)
                        .foregroundColor(.white)
                        .padding(10)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Circle())
                }
                .disabled(isLoading)
            }
            if let lastUpdated = lastUpdated {
                Text("Updated \(lastUpdated, style: .relative) ago · Apple + Whoop → Gemini")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
    }

    // MARK: - States

    private var loadingPlaceholder: some View {
        VStack(spacing: 12) {
            ProgressView().tint(.white)
            Text("Synthesizing recommendation…")
                .font(.subheadline)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.title)
                .foregroundColor(.gray)
            Text("Tap refresh to generate today's recommendation.")
                .font(.subheadline)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func errorView(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Couldn't fetch recommendation", systemImage: "exclamationmark.triangle")
                .font(.subheadline)
                .foregroundColor(.orange)
            Text(message)
                .font(.caption)
                .foregroundColor(.gray)
            Button("Try again", action: refresh)
                .buttonStyle(.borderedProminent)
                .tint(.white.opacity(0.15))
                .foregroundColor(.white)
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
    }

    // MARK: - Recommendation card

    private func recommendationCard(_ rec: AgentManager.WorkoutRecommendation) -> some View {
        let tint = readinessTint(rec.readiness_color)
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("READINESS")
                        .font(.caption2)
                        .foregroundColor(.gray)
                        .tracking(1.5)
                    Text("\(rec.readiness_score)")
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .foregroundColor(tint)
                    Text(rec.readiness_label)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.9))
                }
                Spacer()
                if !rec.has_fresh_vitals {
                    Text("PREVIEW")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.2))
                        .foregroundColor(.orange)
                        .cornerRadius(6)
                }
            }
            Divider().background(Color.white.opacity(0.1))

            Text(rec.headline)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.white)

            HStack(spacing: 12) {
                Label("\(rec.recommended_workout_type)", systemImage: "figure.run")
                Label("\(rec.recommended_duration_min) min", systemImage: "clock")
                Label(rec.recommended_intensity, systemImage: "flame.fill")
            }
            .font(.subheadline)
            .foregroundColor(.white.opacity(0.85))

            Text(rec.reasoning)
                .font(.body)
                .foregroundColor(.white.opacity(0.85))

            if !rec.one_drill.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("ONE DRILL")
                        .font(.caption2)
                        .foregroundColor(.gray)
                        .tracking(1.5)
                    Text(rec.one_drill)
                        .font(.callout)
                        .foregroundColor(.white)
                }
                .padding(.top, 4)
            }
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(16)
    }

    private func signalsSection(_ rec: AgentManager.WorkoutRecommendation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Key signals")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.gray)
            ForEach(rec.key_signals) { signal in
                HStack {
                    Circle()
                        .fill(signalStatusColor(signal.status))
                        .frame(width: 8, height: 8)
                    Text(signal.label)
                        .font(.callout)
                        .foregroundColor(.white.opacity(0.85))
                    Spacer()
                    Text(signal.value)
                        .font(.system(.callout, design: .rounded))
                        .foregroundColor(.white)
                }
                .padding(.vertical, 6)
                .overlay(
                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 0.5),
                    alignment: .bottom
                )
            }
        }
        .padding()
        .background(Color.white.opacity(0.04))
        .cornerRadius(12)
    }

    private func logicSection(_ rec: AgentManager.WorkoutRecommendation) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Logic")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.gray)
            ForEach(rec.logic_breakdown, id: \.self) { line in
                HStack(alignment: .top, spacing: 8) {
                    Text("•").foregroundColor(.gray)
                    Text(line)
                        .font(.callout)
                        .foregroundColor(.white.opacity(0.8))
                }
            }
        }
        .padding()
        .background(Color.white.opacity(0.04))
        .cornerRadius(12)
    }

    // MARK: - Helpers

    private func refresh() {
        isLoading = true
        errorMessage = nil
        agent.fetchUnifiedWorkoutRecommendation { result in
            isLoading = false
            if let r = result {
                rec = r
                lastUpdated = Date()
            } else {
                errorMessage = "Backend didn't return a recommendation. Check that action=workout_recommendation_unified is wired up server-side."
            }
        }
    }

    private func readinessTint(_ color: String) -> Color {
        switch color.lowercased() {
        case "green":  return .green
        case "yellow": return .yellow
        case "red":    return .red
        default:       return .white
        }
    }

    private func signalStatusColor(_ status: String) -> Color {
        switch status.lowercased() {
        case "good":     return .green
        case "warning":  return .yellow
        case "critical": return .red
        default:         return .gray
        }
    }
}

struct GeminiWorkoutRecommendationView_Previews: PreviewProvider {
    static var previews: some View {
        GeminiWorkoutRecommendationView().preferredColorScheme(.dark)
    }
}
