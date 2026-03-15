import SwiftUI
import HealthKit

struct PreviewTabView: View {

    // MARK: - State

    @ObservedObject private var agentManager = AgentManager.shared

    // Diet rating
    @State private var todayDietRating: String? = nil
    @State private var isFetchingPreview: Bool = false

    // Tomorrow preview
    @State private var tomorrowPreview: AgentManager.TomorrowPreview? = nil

    // Chat state
    @State private var showPreviewChat: Bool = false

    // MARK: - Body

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {

                    header

                    // Diet rating picker — always visible if not yet rated today
                    dietRatingSection

                    // Tomorrow preview — shows after diet rating is saved
                    if tomorrowPreview != nil || isFetchingPreview {
                        tomorrowSection
                    }

                    Spacer(minLength: 40)
                }
            }
            .background(Color.black.edgesIgnoringSafeArea(.all))
            .onAppear { onViewAppear() }
        }
        .sheet(isPresented: $showPreviewChat) {
            if let preview = tomorrowPreview, let dietRating = todayDietRating {
                let todayWorkouts = getTodayWorkoutsSummary()
                CoachChatView(context: .tomorrowPreview(preview: preview, todayWorkouts: todayWorkouts, dietRating: dietRating))
            }
        }
    }

    // MARK: - On Appear

    func onViewAppear() {
        // Load persisted diet rating for today
        todayDietRating = NotificationManager.dietRating(for: NotificationManager.todayDateString())

        // Only restore preview if user has already rated their diet today
        if let rating = todayDietRating,
           let cached = agentManager.cachedTomorrowPreview,
           let previewDate = agentManager.value(forKey: "tomorrowPreviewDate") as? String,
           previewDate == NotificationManager.todayDateString() {
            tomorrowPreview = cached
            print("✅ Restored today's preview (diet: \(rating))")
        } else {
            // No rating yet or stale preview — clear it
            tomorrowPreview = nil
            print("📝 No preview - waiting for diet rating")
        }
    }

    // Helper to get today's workouts summary
    func getTodayWorkoutsSummary() -> String {
        return "Today's workouts summary"
    }

    // MARK: - Header

    var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Tomorrow's Preview")
                    .font(.largeTitle).bold()
                    .foregroundColor(.white)
                Text(formattedDate())
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            Spacer()
            Button(action: refreshPreview) {
                Image(systemName: "arrow.clockwise")
                    .foregroundColor(.orange)
                    .font(.title3)
            }
        }
        .padding(.horizontal)
        .padding(.top, 40)
    }

    // MARK: - Diet Rating Section

    var dietRatingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let rating = todayDietRating {
                // Already rated — show confirmation chip + allow change
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Diet rated: \(dietRatingLabel(rating))")
                        .font(.subheadline)
                        .foregroundColor(.white)
                    Spacer()
                    Button("Change") {
                        todayDietRating = nil  // allow re-rating
                    }
                    .font(.caption)
                    .foregroundColor(.orange)
                }
                .padding(12)
                .background(Color.green.opacity(0.08))
                .cornerRadius(12)
                .padding(.horizontal)
            } else {
                // Not yet rated — show picker
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "fork.knife")
                            .foregroundColor(.orange)
                        Text("How was your diet today?")
                            .font(.subheadline).bold()
                            .foregroundColor(.white)
                    }

                    HStack(spacing: 8) {
                        ForEach(dietOptions, id: \.key) { option in
                            Button(action: { saveDietRating(option.key) }) {
                                Text(option.label)
                                    .font(.caption).bold()
                                    .multilineTextAlignment(.center)
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 6)
                                    .frame(maxWidth: .infinity)
                                    .background(option.color.opacity(0.15))
                                    .foregroundColor(option.color)
                                    .cornerRadius(10)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(option.color.opacity(0.4), lineWidth: 1)
                                    )
                            }
                        }
                    }
                }
                .padding(14)
                .background(Color.white.opacity(0.05))
                .cornerRadius(16)
                .padding(.horizontal)
            }
        }
    }

    struct DietOption {
        let key: String
        let label: String
        let color: Color
    }

    var dietOptions: [DietOption] {[
        DietOption(key: "nailed_it",  label: "🟢 Nailed it",   color: .green),
        DietOption(key: "minor_good", label: "🔵 Minor good",  color: .blue),
        DietOption(key: "minor_bad",  label: "🟡 Minor bad",   color: .yellow),
        DietOption(key: "fully_bad",  label: "🔴 Fully bad",   color: .red)
    ]}

    func saveDietRating(_ rating: String) {
        // Persist
        let key = "diet_rating_\(NotificationManager.todayDateString())"
        UserDefaults.standard.set(rating, forKey: key)
        todayDietRating = rating
        print("💾 Diet rating saved: \(rating)")

        // Immediately trigger tomorrow preview in background
        isFetchingPreview = true
        print("🔄 Generating tomorrow's preview...")
        AgentManager.shared.fetchTomorrowPreview(dietRating: rating) { preview in
            isFetchingPreview = false
            tomorrowPreview = preview
            if preview != nil {
                print("✅ Preview generated successfully")
            } else {
                print("❌ Failed to generate preview")
            }
        }
    }

    func dietRatingLabel(_ key: String) -> String {
        switch key {
        case "nailed_it":  return "Nailed it 🟢"
        case "minor_good": return "Minor good 🔵"
        case "minor_bad":  return "Minor bad 🟡"
        case "fully_bad":  return "Fully bad 🔴"
        default:           return key
        }
    }

    // MARK: - Tomorrow Preview Section

    var tomorrowSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "moon.stars.fill")
                    .foregroundColor(.indigo)
                Text("Tomorrow's Workout Plan")
                    .font(.subheadline).bold()
                    .foregroundColor(.white)
                Spacer()
                Text("⚡ Final check in the morning")
                    .font(.caption2)
                    .foregroundColor(.gray)
            }

            if isFetchingPreview {
                HStack(spacing: 10) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .indigo))
                    Text("Generating preview...")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                .padding(.vertical, 8)
            } else if let preview = tomorrowPreview {
                // Headline
                Text(preview.preview_headline)
                    .font(.title3).bold()
                    .foregroundColor(.white)

                // Workout pills
                HStack(spacing: 12) {
                    previewPill(icon: workoutIcon(preview.preview_workout_type),
                                label: preview.preview_workout_type,
                                color: .indigo)
                    previewPill(icon: "clock",
                                label: preview.preview_duration_range,
                                color: .purple)
                    previewPill(icon: "bolt.fill",
                                label: preview.preview_intensity_ceiling,
                                color: .blue)
                }

                // Exact Prescription (NEW)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Workout Details")
                        .font(.caption).bold()
                        .foregroundColor(.indigo)
                        .tracking(1.5).textCase(.uppercase)

                    Text(preview.preview_exact_prescription)
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .background(Color.indigo.opacity(0.12))
                .cornerRadius(12)

                // Reasoning
                Text(preview.preview_reasoning)
                    .font(.caption)
                    .foregroundColor(.gray)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)

                // Caveat
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.caption)
                        .foregroundColor(.gray)
                    Text(preview.caveat)
                        .font(.caption2)
                        .foregroundColor(.gray)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Chat Button for Preview
                if let _ = todayDietRating {
                    Button(action: { showPreviewChat = true }) {
                        HStack(spacing: 8) {
                            Image(systemName: "bubble.left.and.bubble.right.fill")
                                .font(.caption)
                            Text("Ask about tomorrow")
                                .font(.caption).bold()
                        }
                        .foregroundColor(.indigo)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(Color.indigo.opacity(0.15))
                        .cornerRadius(8)
                    }
                    .padding(.top, 4)
                }
            }
        }
        .padding()
        .background(Color.indigo.opacity(0.07))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.indigo.opacity(0.2), lineWidth: 1)
        )
        .padding(.horizontal)
    }

    func previewPill(icon: String, label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(label)
                .font(.caption2).bold()
                .lineLimit(1)
        }
        .foregroundColor(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(color.opacity(0.12))
        .cornerRadius(8)
    }

    // MARK: - Helpers

    func refreshPreview() {
        guard let rating = todayDietRating else { return }
        isFetchingPreview = true
        AgentManager.shared.fetchTomorrowPreview(dietRating: rating) { preview in
            isFetchingPreview = false
            tomorrowPreview = preview
        }
    }

    func formattedDate() -> String {
        let f = DateFormatter(); f.dateFormat = "EEEE, MMM d"; return f.string(from: Date())
    }

    func workoutIcon(_ type: String) -> String {
        let t = type.lowercased()
        if t.contains("run")      { return "figure.run" }
        if t.contains("strength") { return "dumbbell.fill" }
        if t.contains("hiit")     { return "figure.cross.training" }
        if t.contains("yoga") || t.contains("mobility") { return "figure.yoga" }
        if t.contains("cycl") || t.contains("ride") { return "bicycle" }
        if t.contains("swim")     { return "figure.pool.swim" }
        if t.contains("walk")     { return "figure.walk" }
        if t.contains("rest")     { return "bed.double.fill" }
        return "figure.mixed.cardio"
    }
}
