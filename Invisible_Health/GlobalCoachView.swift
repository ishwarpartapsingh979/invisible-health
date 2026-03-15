import SwiftUI
import HealthKit

struct GlobalCoachView: View {
    @State private var workouts: [HKWorkout] = []
    @State private var isLoading: Bool = false
    @State private var showChat: Bool = false
    @State private var globalSummary: String = ""
    @State private var selectedTimeRange: TimeRange = .month

    enum TimeRange: String, CaseIterable {
        case day = "Day"
        case week = "Week"
        case month = "Month"

        var days: Int {
            switch self {
            case .day: return 1
            case .week: return 7
            case .month: return 30
            }
        }

        var displayText: String {
            switch self {
            case .day: return "Last 24 Hours"
            case .week: return "Last 7 Days"
            case .month: return "Last 30 Days"
            }
        }
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Header
                        header

                        // Time Range Selector
                        timeRangeSelector

                        if isLoading {
                            loadingView
                        } else if !workouts.isEmpty {
                            // Stats Cards
                            statsSection

                            // Global Summary
                            summaryCard

                            // Chat Button
                            chatButton

                            // Recent Workouts List
                            workoutsListSection
                        } else {
                            emptyState
                        }
                    }
                    .padding()
                }
            }
            .navigationBarHidden(true)
        }
        .sheet(isPresented: $showChat) {
            if !workouts.isEmpty {
                CoachChatView(context: .globalWorkouts(workouts: workouts, initialSummary: globalSummary))
            }
        }
        .onAppear {
            loadWorkouts()
        }
    }

    // MARK: - Header

    var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Performance Director")
                    .font(.largeTitle).bold()
                    .foregroundColor(.white)
                Text(selectedTimeRange.displayText)
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            Spacer()
            Button(action: loadWorkouts) {
                Image(systemName: "arrow.clockwise")
                    .foregroundColor(.orange)
                    .font(.title3)
            }
        }
        .padding(.top, 40)
    }

    // MARK: - Time Range Selector

    var timeRangeSelector: some View {
        Picker("Time Range", selection: $selectedTimeRange) {
            ForEach(TimeRange.allCases, id: \.self) { range in
                Text(range.rawValue).tag(range)
            }
        }
        .pickerStyle(SegmentedPickerStyle())
        .onChange(of: selectedTimeRange) { newValue in
            print("🔄 Time range changed to: \(newValue.rawValue) (\(newValue.days) days)")
            workouts = [] // Clear workouts immediately
            globalSummary = ""
            loadWorkouts()
        }
    }

    // MARK: - Stats Section

    var statsSection: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
            StatCard(title: "Total Workouts", value: "\(workouts.count)", icon: "figure.run", color: .blue)
            StatCard(title: "Total Volume", value: formatTotalDuration(), icon: "clock.fill", color: .green)
            StatCard(title: "Avg Duration", value: formatAvgDuration(), icon: "timer", color: .orange)
            StatCard(title: "Total Calories", value: formatTotalCalories(), icon: "flame.fill", color: .red)
        }
    }

    // MARK: - Summary Card

    var summaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "brain.head.profile")
                    .foregroundColor(.purple)
                Text("AI Analysis")
                    .font(.headline)
                    .foregroundColor(.white)
            }

            if globalSummary.isEmpty {
                Button(action: generateSummary) {
                    HStack {
                        Image(systemName: "sparkles")
                        Text("Generate AI Summary")
                            .font(.subheadline).bold()
                    }
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.purple)
                    .cornerRadius(12)
                }
            } else {
                Text(globalSummary)
                    .font(.body)
                    .foregroundColor(.gray)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(16)
    }

    // MARK: - Chat Button

    var chatButton: some View {
        Button(action: {
            if globalSummary.isEmpty {
                generateSummary()
            }
            showChat = true
        }) {
            HStack {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.title3)
                Text("Ask Performance Director")
                    .font(.headline).bold()
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
            }
            .foregroundColor(.black)
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.green)
            .cornerRadius(16)
        }
    }

    // MARK: - Workouts List

    var workoutsListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Workouts")
                .font(.headline)
                .foregroundColor(.white)

            ForEach(workouts.prefix(10), id: \.uuid) { workout in
                WorkoutRow(workout: workout)
            }
        }
    }

    // MARK: - Loading View

    var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .orange))
                .scaleEffect(1.5)
            Text("Loading workouts...")
                .foregroundColor(.gray)
                .font(.subheadline)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    // MARK: - Empty State

    var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "figure.run.circle")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            Text("No workouts in the \(selectedTimeRange.displayText.lowercased())")
                .font(.headline)
                .foregroundColor(.gray)
            Text("Start training to see your performance analysis")
                .font(.caption)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    // MARK: - Helper Functions

    func loadWorkouts() {
        isLoading = true
        globalSummary = "" // Reset summary when time range changes
        HealthManager.shared.fetchRecentWorkouts(days: selectedTimeRange.days) { fetchedWorkouts in
            self.workouts = fetchedWorkouts
            self.isLoading = false

            // Auto-generate summary if we have workouts
            if !fetchedWorkouts.isEmpty {
                self.generateSummary()
            }
        }
    }

    func generateSummary() {
        // Generate a comprehensive AI-powered summary
        isLoading = true

        // Create a system message asking for an overview
        let timeRangeText = selectedTimeRange.displayText.lowercased()
        let initialPrompt: [[String: String]] = [
            ["role": "user", "text": "Give me a comprehensive overview of my \(timeRangeText) of training. Include volume trends, recovery patterns, and key insights."]
        ]

        AgentManager.shared.chatWithCoachGlobal(workouts: workouts, history: initialPrompt) { message in
            self.isLoading = false
            self.globalSummary = message
        }
    }

    func formatTotalDuration() -> String {
        let totalSeconds = workouts.reduce(0.0) { $0 + $1.duration }
        let hours = Int(totalSeconds / 3600)
        return "\(hours)h"
    }

    func formatAvgDuration() -> String {
        guard !workouts.isEmpty else { return "0m" }
        let avgSeconds = workouts.reduce(0.0) { $0 + $1.duration } / Double(workouts.count)
        let mins = Int(avgSeconds / 60)
        return "\(mins)m"
    }

    func formatTotalCalories() -> String {
        let totalCals = workouts.reduce(0.0) { sum, workout in
            let cals = workout.statistics(for: HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!)?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
            return sum + cals
        }
        return "\(Int(totalCals))"
    }
}

// MARK: - Stat Card

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.title3)
                Spacer()
            }

            Text(value)
                .font(.title).bold()
                .foregroundColor(.white)

            Text(title)
                .font(.caption)
                .foregroundColor(.gray)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05))
        .cornerRadius(16)
    }
}

// MARK: - Workout Row

struct WorkoutRow: View {
    let workout: HKWorkout

    var body: some View {
        HStack {
            Image(systemName: workoutIcon)
                .foregroundColor(.orange)
                .font(.title3)
                .frame(width: 40, height: 40)
                .background(Color.orange.opacity(0.15))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(workout.workoutActivityType.name)
                    .font(.subheadline).bold()
                    .foregroundColor(.white)
                Text(workout.startDate.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundColor(.gray)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("\(Int(workout.duration / 60))m")
                    .font(.subheadline).bold()
                    .foregroundColor(.white)
                if let cals = workout.statistics(for: HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!)?.sumQuantity()?.doubleValue(for: .kilocalorie()) {
                    Text("\(Int(cals)) kcal")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
        }
        .padding()
        .background(Color.white.opacity(0.03))
        .cornerRadius(12)
    }

    var workoutIcon: String {
        switch workout.workoutActivityType {
        case .running: return "figure.run"
        case .cycling: return "bicycle"
        case .swimming: return "figure.pool.swim"
        case .walking: return "figure.walk"
        case .hiking: return "figure.hiking"
        case .traditionalStrengthTraining, .functionalStrengthTraining: return "dumbbell.fill"
        case .highIntensityIntervalTraining: return "figure.cross.training"
        case .yoga: return "figure.yoga"
        default: return "figure.mixed.cardio"
        }
    }
}
