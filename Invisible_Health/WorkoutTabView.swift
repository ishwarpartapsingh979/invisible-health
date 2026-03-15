import SwiftUI
import WorkoutKit
import HealthKit

struct WorkoutTabView: View {

    // MARK: - State

    @ObservedObject private var agentManager = AgentManager.shared

    @State private var recommendation: AgentManager.WorkoutRecommendation? = nil
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil
    @State private var showLogicBreakdown: Bool = false
    @State private var watchSendState: WatchSendState = .idle
    @State private var workoutPlanToPreview: WorkoutPlan? = nil
    @State private var showWorkoutPreview: Bool = false

    // Chat state
    @State private var showRecommendationChat: Bool = false

    // Optional context inputs
    @State private var optionalContext: String = ""
    @State private var finalFeedback: String = ""

    enum WatchSendState {
        case idle, sending, sent, failed(String)
    }

    // MARK: - Body

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {

                    header

                    // Optional context input (always visible before recommendation)
                    optionalContextSection

                    if isLoading {
                        loadingView
                    } else if let rec = recommendation {
                        readinessRing(rec)
                        headlineCard(rec)
                        signalsGrid(rec)
                        prescriptionCard(rec)
                        logicBreakdownSection(rec)
                        drillCard(rec)
                        chatButton(rec)
                        acceptButton(rec)

                        // Final feedback (after workout is created)
                        finalFeedbackSection
                    } else {
                        emptyState
                    }

                    Spacer(minLength: 40)
                }
            }
            .background(Color.black.edgesIgnoringSafeArea(.all))
            .onAppear { onViewAppear() }
            .workoutPreview(workoutPlanToPreview ?? WorkoutPlan(.goal(SingleGoalWorkout(activity: .other, location: .outdoor, goal: .open))), isPresented: $showWorkoutPreview)
        }
        .sheet(isPresented: $showRecommendationChat) {
            if let rec = recommendation {
                CoachChatView(context: .morningRecommendation(recommendation: rec))
            }
        }
    }

    // MARK: - On Appear

    func onViewAppear() {
        // If morning audit already auto-computed a recommendation, show it immediately
        if let cached = agentManager.cachedMorningRecommendation {
            recommendation = cached
            // Clear yesterday's preview now that today's recommendation is ready
            agentManager.cachedTomorrowPreview = nil
        } else {
            load()
        }
    }

    // MARK: - Header

    var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Today's Workout")
                    .font(.largeTitle).bold()
                    .foregroundColor(.white)
                Text(formattedDate())
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            Spacer()
            Button(action: load) {
                Image(systemName: "arrow.clockwise")
                    .foregroundColor(.orange)
                    .font(.title3)
            }
        }
        .padding(.horizontal)
        .padding(.top, 40)
    }

    // MARK: - Optional Context Section

    var optionalContextSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "text.bubble")
                    .foregroundColor(.blue)
                Text("Optional Context (Sleep, Conditions)")
                    .font(.subheadline).bold()
                    .foregroundColor(.white)
            }

            TextField("e.g., 6 hrs sleep, sore knees, feeling tired...", text: $optionalContext)
                .padding(12)
                .background(Color.white.opacity(0.08))
                .foregroundColor(.white)
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                )

            Text("This info will help personalize your workout recommendation")
                .font(.caption2)
                .foregroundColor(.gray)
        }
        .padding()
        .background(Color.blue.opacity(0.08))
        .cornerRadius(16)
        .padding(.horizontal)
    }

    // MARK: - Loading

    var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .orange))
                .scaleEffect(1.5)
            Text("Analysing your signals...")
                .foregroundColor(.gray)
                .font(.subheadline)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    // MARK: - Empty State

    var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 50))
                .foregroundColor(.gray)
            Text("No recommendation yet.")
                .foregroundColor(.gray)
            if let err = errorMessage {
                Text(err)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            Button(action: load) {
                Text("Try Again")
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(Color.orange)
                    .foregroundColor(.black)
                    .cornerRadius(10)
            }
        }
        .padding(.top, 40)
    }

    // MARK: - Readiness Ring

    func readinessRing(_ rec: AgentManager.WorkoutRecommendation) -> some View {
        let color = ringColor(rec.readiness_color)
        let progress = Double(rec.readiness_score) / 100.0

        return VStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(color.opacity(0.15), lineWidth: 16)
                    .frame(width: 160, height: 160)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(color, style: StrokeStyle(lineWidth: 16, lineCap: .round))
                    .frame(width: 160, height: 160)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.8), value: progress)
                VStack(spacing: 4) {
                    Text("\(rec.readiness_score)")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text(rec.readiness_label)
                        .font(.caption).fontWeight(.semibold)
                        .foregroundColor(color)
                }
            }
            Text("Readiness Score")
                .font(.caption).foregroundColor(.gray)
                .tracking(1.5).textCase(.uppercase)
        }
        .padding(.top, 10)
    }

    // MARK: - Headline Card

    func headlineCard(_ rec: AgentManager.WorkoutRecommendation) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(rec.headline)
                .font(.title3).bold().foregroundColor(.white)
            Text(rec.reasoning)
                .font(.subheadline).foregroundColor(.gray)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05))
        .cornerRadius(16)
        .padding(.horizontal)
    }

    // MARK: - Signals Grid

    func signalsGrid(_ rec: AgentManager.WorkoutRecommendation) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Signal Board")
                .font(.caption).foregroundColor(.gray)
                .tracking(1.5).textCase(.uppercase)
                .padding(.horizontal)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(rec.key_signals) { signal in SignalCard(signal: signal) }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Prescription Card

    func prescriptionCard(_ rec: AgentManager.WorkoutRecommendation) -> some View {
        let color = ringColor(rec.readiness_color)
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: workoutIcon(rec.recommended_workout_type))
                    .font(.title2).foregroundColor(color)
                    .frame(width: 44, height: 44)
                    .background(color.opacity(0.15)).clipShape(Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(rec.recommended_workout_type)
                        .font(.headline).bold().foregroundColor(.white)
                    Text(rec.recommended_intensity)
                        .font(.caption).foregroundColor(color)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(rec.recommended_duration_min)")
                        .font(.title2).bold().foregroundColor(.white)
                    Text("min").font(.caption).foregroundColor(.gray)
                }
            }
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(color.opacity(0.3), lineWidth: 1))
        .padding(.horizontal)
    }

    // MARK: - Logic Breakdown

    func logicBreakdownSection(_ rec: AgentManager.WorkoutRecommendation) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.25)) { showLogicBreakdown.toggle() }
            }) {
                HStack {
                    Image(systemName: "function").foregroundColor(.orange).font(.subheadline)
                    Text("Why this recommendation?")
                        .font(.subheadline).bold().foregroundColor(.white)
                    Spacer()
                    Image(systemName: showLogicBreakdown ? "chevron.up" : "chevron.down")
                        .foregroundColor(.gray).font(.caption)
                }
                .padding()
                .background(Color.white.opacity(0.05))
                .cornerRadius(16, corners: [.topLeft, .topRight])
                .cornerRadius(showLogicBreakdown ? 0 : 16)
            }

            if showLogicBreakdown {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(rec.logic_breakdown.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 12) {
                            ZStack {
                                Circle().fill(Color.orange.opacity(0.15)).frame(width: 26, height: 26)
                                Text(index < rec.logic_breakdown.count - 1 ? "\(index + 1)" : "✓")
                                    .font(.caption2).bold().foregroundColor(.orange)
                            }
                            Text(step)
                                .font(.subheadline)
                                .foregroundColor(index == rec.logic_breakdown.count - 1 ? .white : .gray)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding()
                .background(Color.white.opacity(0.03))
                .cornerRadius(16, corners: [.bottomLeft, .bottomRight])
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Drill Card

    func drillCard(_ rec: AgentManager.WorkoutRecommendation) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "figure.strengthtraining.functional")
                .font(.title2).foregroundColor(.orange).frame(width: 36)
            VStack(alignment: .leading, spacing: 4) {
                Text("Activation Drill")
                    .font(.caption).foregroundColor(.gray).tracking(1).textCase(.uppercase)
                Text(rec.one_drill)
                    .font(.subheadline).foregroundColor(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08))
        .cornerRadius(16)
        .padding(.horizontal)
    }

    // MARK: - Chat Button

    func chatButton(_ rec: AgentManager.WorkoutRecommendation) -> some View {
        Button(action: { showRecommendationChat = true }) {
            HStack(spacing: 12) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.title3)
                Text("Ask Coach about this workout")
                    .font(.subheadline).bold()
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
            }
            .foregroundColor(.white)
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.green.opacity(0.8))
            .cornerRadius(16)
        }
        .padding(.horizontal)
    }

    // MARK: - Accept & Send to Watch

    @ViewBuilder
    func acceptButton(_ rec: AgentManager.WorkoutRecommendation) -> some View {
        VStack(spacing: 10) {
            if rec.recommended_workout_type.lowercased().contains("rest") {
                HStack(spacing: 10) {
                    Image(systemName: "bed.double.fill").foregroundColor(.blue)
                    Text("Rest Day — no workout to send")
                        .font(.subheadline).foregroundColor(.gray)
                }
                .padding().frame(maxWidth: .infinity)
                .background(Color.white.opacity(0.05)).cornerRadius(16)
                .padding(.horizontal)
            } else if !rec.has_fresh_vitals {
                // Preview mode — no push to watch
                VStack(spacing: 8) {
                    HStack(spacing: 10) {
                        Image(systemName: "eye.fill").foregroundColor(.indigo)
                        Text("Preview Only")
                            .font(.subheadline).bold().foregroundColor(.white)
                    }
                    Text("Put on your watch tomorrow morning to get the final plan with Push to Watch")
                        .font(.caption).foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding().frame(maxWidth: .infinity)
                .background(Color.indigo.opacity(0.1)).cornerRadius(16)
                .padding(.horizontal)
            } else {
                switch watchSendState {
                case .idle:
                    Button(action: { sendToWatch(rec) }) {
                        HStack(spacing: 12) {
                            Image(systemName: "applewatch").font(.title3)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Accept & Send to Watch")
                                    .font(.headline).bold()
                                Text("\(rec.recommended_workout_type) · \(rec.recommended_duration_min) min · \(rec.recommended_intensity)")
                                    .font(.caption).opacity(0.8)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption)
                        }
                        .foregroundColor(.black)
                        .padding().frame(maxWidth: .infinity)
                        .background(ringColor(rec.readiness_color))
                        .cornerRadius(16).padding(.horizontal)
                    }

                case .sending:
                    HStack(spacing: 10) {
                        ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white))
                        Text("Sending to Watch...").font(.subheadline).foregroundColor(.white)
                    }
                    .padding().frame(maxWidth: .infinity)
                    .background(Color.gray.opacity(0.3)).cornerRadius(16).padding(.horizontal)

                case .sent:
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill").foregroundColor(.green).font(.title3)
                        Text("Workout sent to Apple Watch!").font(.subheadline).bold().foregroundColor(.green)
                    }
                    .padding().frame(maxWidth: .infinity)
                    .background(Color.green.opacity(0.1)).cornerRadius(16).padding(.horizontal)

                case .failed(let reason):
                    VStack(spacing: 6) {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.red)
                            Text("Could not send to Watch").font(.subheadline).bold().foregroundColor(.red)
                        }
                        Text(reason).font(.caption).foregroundColor(.gray).multilineTextAlignment(.center)
                        Button("Try Again") { sendToWatch(rec) }.font(.caption).foregroundColor(.orange)
                    }
                    .padding().frame(maxWidth: .infinity)
                    .background(Color.red.opacity(0.08)).cornerRadius(16).padding(.horizontal)
                }
            }
        }
        .padding(.bottom, 10)
    }

    // MARK: - Final Feedback Section

    var finalFeedbackSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "pencil.and.list.clipboard")
                    .foregroundColor(.purple)
                Text("Final Feedback (Optional)")
                    .font(.subheadline).bold()
                    .foregroundColor(.white)
            }

            TextField("How does this recommendation look? Any adjustments needed?", text: $finalFeedback)
                .padding(12)
                .background(Color.white.opacity(0.08))
                .foregroundColor(.white)
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.purple.opacity(0.3), lineWidth: 1)
                )

            Text("This feedback will help improve future recommendations (saved for later)")
                .font(.caption2)
                .foregroundColor(.gray)
        }
        .padding()
        .background(Color.purple.opacity(0.08))
        .cornerRadius(16)
        .padding(.horizontal)
    }

    // MARK: - WorkoutKit

    func sendToWatch(_ rec: AgentManager.WorkoutRecommendation) {
        let activityType = mapToHKWorkoutActivityType(rec.recommended_workout_type)
        let durationSeconds = Double(rec.recommended_duration_min) * 60
        let goal = WorkoutGoal.time(durationSeconds, .seconds)
        let singleGoalWorkout = SingleGoalWorkout(
            activity: activityType,
            location: workoutLocation(rec.recommended_workout_type),
            goal: goal
        )
        workoutPlanToPreview = WorkoutPlan(.goal(singleGoalWorkout))
        showWorkoutPreview = true
        watchSendState = .sent
    }

    // MARK: - Helpers

    func load() {
        isLoading = true
        errorMessage = nil
        watchSendState = .idle
        let context = optionalContext.trimmingCharacters(in: .whitespacesAndNewlines)
        AgentManager.shared.fetchWorkoutRecommendation(optionalContext: context.isEmpty ? nil : context) { rec in
            isLoading = false
            if let rec = rec { recommendation = rec }
            else { errorMessage = "Could not load recommendation. Check your connection." }
        }
    }

    func mapToHKWorkoutActivityType(_ type: String) -> HKWorkoutActivityType {
        let t = type.lowercased()
        if t.contains("run") || t.contains("tempo") || t.contains("interval") { return .running }
        if t.contains("strength") || t.contains("lift") || t.contains("weight") { return .traditionalStrengthTraining }
        if t.contains("hiit") || t.contains("circuit") { return .highIntensityIntervalTraining }
        if t.contains("yoga") || t.contains("stretch") || t.contains("mobility") { return .yoga }
        if t.contains("cycl") || t.contains("ride") || t.contains("bike") { return .cycling }
        if t.contains("swim") { return .swimming }
        if t.contains("walk") { return .walking }
        if t.contains("hike") { return .hiking }
        if t.contains("row") { return .rowing }
        if t.contains("zone 2") { return .running }
        return .other
    }

    func workoutLocation(_ type: String) -> HKWorkoutSessionLocationType {
        let t = type.lowercased()
        if t.contains("treadmill") || t.contains("indoor") || t.contains("strength") ||
           t.contains("hiit") || t.contains("yoga") || t.contains("row") { return .indoor }
        return .outdoor
    }

    func formattedDate() -> String {
        let f = DateFormatter(); f.dateFormat = "EEEE, MMM d"; return f.string(from: Date())
    }

    func ringColor(_ colorName: String) -> Color {
        switch colorName.lowercased() {
        case "green":  return .green
        case "yellow": return .yellow
        case "orange": return .orange
        case "red":    return .red
        default:       return .orange
        }
    }

    func workoutIcon(_ type: String) -> String {
        let t = type.lowercased()
        if t.contains("run")      { return "figure.run" }
        if t.contains("strength") { return "dumbbell.fill" }
        if t.contains("hiit")     { return "figure.cross.training" }
        if t.contains("yoga")     { return "figure.yoga" }
        if t.contains("cycl") || t.contains("ride") { return "bicycle" }
        if t.contains("swim")     { return "figure.pool.swim" }
        if t.contains("walk")     { return "figure.walk" }
        if t.contains("rest")     { return "bed.double.fill" }
        return "figure.mixed.cardio"
    }
}

// MARK: - Signal Card

struct SignalCard: View {
    let signal: AgentManager.RecommendationSignal

    var statusColor: Color {
        switch signal.status.lowercased() {
        case "good":     return .green
        case "warning":  return .yellow
        case "critical": return .red
        default:         return .gray
        }
    }

    var statusIcon: String {
        switch signal.status.lowercased() {
        case "good":     return "checkmark.circle.fill"
        case "warning":  return "exclamationmark.triangle.fill"
        case "critical": return "xmark.circle.fill"
        default:         return "minus.circle"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(signal.label).font(.caption).foregroundColor(.gray)
                Spacer()
                Image(systemName: statusIcon).foregroundColor(statusColor).font(.caption)
            }
            Text(signal.value).font(.subheadline).bold().foregroundColor(.white)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05)).cornerRadius(12)
    }
}

// MARK: - Corner Radius Helper

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}
