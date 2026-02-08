import SwiftUI
import HealthKit

struct WorkoutView: View {
    @State private var workouts: [HKWorkout] = []
    @State private var showingGoalSheet = false
    
    var body: some View {
        NavigationView {
            VStack {
                // Header
                HStack {
                    Text("Workout Feed")
                        .font(.largeTitle)
                        .bold()
                        .foregroundColor(.white)
                    Spacer()
                    
                    // Goal Button (New)
                    Button(action: { showingGoalSheet = true }) {
                        Image(systemName: "target")
                            .foregroundColor(.red)
                            .font(.title3)
                            .padding(8)
                            .background(Color.red.opacity(0.1))
                            .clipShape(Circle())
                    }
                    
                    Button(action: { fetchWorkouts() }) {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(.orange)
                    }
                }
                .sheet(isPresented: $showingGoalSheet) {
                    GoalSettingView()
                }
                .padding()
                .padding(.top, 40)
                
                if workouts.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "figure.run.circle")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        Text("No workouts logged today.")
                            .foregroundColor(.gray)
                        
                        Text("Syncing with Apple Health...")
                            .font(.caption)
                            .foregroundColor(.gray.opacity(0.5))
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 20) {
                            ForEach(groupedWorkouts(workouts), id: \.date) { section in
                                VStack(alignment: .leading) {
                                    Text(sectionTitle(for: section.date))
                                        .font(.headline)
                                        .foregroundColor(.gray)
                                        .padding(.horizontal)
                                    
                                    ForEach(section.workouts, id: \.self) { workout in
                                        NavigationLink(destination: WorkoutDetailView(workout: workout)) {
                                            WorkoutCard(workout: workout)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.top)
                    }
                }
            }
            .background(Color.black.edgesIgnoringSafeArea(.all))
            .onAppear {
                fetchWorkouts()
            }
        }
    }
    
    // Grouping Logic
    func groupedWorkouts(_ workouts: [HKWorkout]) -> [WorkoutSection] {
        let grouped = Dictionary(grouping: workouts) { (workout) -> Date in
            return Calendar.current.startOfDay(for: workout.startDate)
        }
        
        return grouped.sorted { $0.key > $1.key }.map { WorkoutSection(date: $0.key, workouts: $0.value) }
    }
    
    func sectionTitle(for date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: date)
    }
    
    func fetchWorkouts() {
        // Fetch last 7 days (Today + 6 previous days)
        HealthManager.shared.fetchRecentWorkouts(days: 7) { fetchedWorkouts in
            self.workouts = fetchedWorkouts
        }
    }
}

// Helper to Group Workouts by Date
struct WorkoutSection: Identifiable {
    let id = UUID()
    let date: Date
    let workouts: [HKWorkout]
}


struct WorkoutCard: View {
    let workout: HKWorkout
    
    var body: some View {
        HStack {
            // Icon
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.2))
                    .frame(width: 50, height: 50)
                
                Image(systemName: getIcon(for: workout))
                    .foregroundColor(.orange)
                    .font(.title2)
            }
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(workout.workoutActivityType.name)
                    .font(.headline)
                    .foregroundColor(.white)
                
                Text("\(formatDuration(workout.duration)) • \(formatCalories(workout)) kcal")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            // Chevron
            Image(systemName: "chevron.right")
                .foregroundColor(.gray)
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground).opacity(0.1))
        .cornerRadius(15)
    }
    
    func getIcon(for workout: HKWorkout) -> String {
        switch workout.workoutActivityType {
        case .running: return "figure.run"
        case .walking: return "figure.walk"
        case .traditionalStrengthTraining, .functionalStrengthTraining: return "dumbbell.fill"
        case .highIntensityIntervalTraining: return "figure.cross.training"
        case .cycling: return "bicycle"
        case .swimming: return "figure.pool.swim"
        case .yoga: return "figure.yoga"
        case .dance: return "figure.dance"
        case .hiking: return "figure.hiking"
        case .rowing: return "figure.rower"
        case .soccer: return "sportscourt.fill"
        case .tableTennis: return "figure.table.tennis"
        case .tennis: return "figure.tennis"
        case .basketball: return "figure.basketball"
        case .baseball: return "figure.baseball"
        case .volleyball: return "figure.volleyball"
        case .badminton: return "figure.badminton"
        case .golf: return "figure.golf"
        case .downhillSkiing: return "figure.skiing.downhill"
        case .snowboarding: return "figure.snowboarding"
        default: return "figure.mixed.cardio"
        }
    }
    
    func formatDuration(_ duration: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: duration) ?? "0m"
    }
    
    func formatCalories(_ workout: HKWorkout) -> String {
        let calories = workout.statistics(for: HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!)?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
        return String(format: "%.0f", calories)
    }
}

extension HKWorkoutActivityType {
    var name: String {
        switch self {
        case .running: return "Running"
        case .walking: return "Walking"
        case .traditionalStrengthTraining: return "Strength Training"
        case .functionalStrengthTraining: return "Functional Training"
        case .highIntensityIntervalTraining: return "HIIT"
        case .yoga: return "Yoga"
        case .cycling: return "Cycling"
        case .swimming: return "Swimming"
        case .hiking: return "Hiking"
        case .rowing: return "Rowing"
        case .dance: return "Dance"
        case .soccer: return "Football"
        case .tableTennis: return "Table Tennis"
        case .tennis: return "Tennis"
        case .basketball: return "Basketball"
        case .baseball: return "Baseball"
        case .volleyball: return "Volleyball"
        case .badminton: return "Badminton"
        case .golf: return "Golf"
        case .downhillSkiing: return "Skiing"
        case .snowboarding: return "Snowboarding"
        default: return "Workout"
        }
    }
}

struct GoalSettingView: View {
    @Environment(\.dismiss) var dismiss
    @State private var eventName: String = ""
    @State private var eventDate: Date = Date()
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Target Event")) {
                    TextField("Event Name (e.g. Marathon)", text: $eventName)
                    DatePicker("Date", selection: $eventDate, displayedComponents: .date)
                }
                
                Section {
                    Button("Save Goal") {
                        saveGoal()
                        dismiss()
                    }
                    .disabled(eventName.isEmpty)
                    
                    Button("Clear Goal") {
                        clearGoal()
                        dismiss()
                    }
                    .foregroundColor(.red)
                }
                
                Section(footer: Text("The AI Coach will analyze your workouts based on this goal.")) {
                    EmptyView()
                }
            }
            .navigationTitle("Set Goal 🎯")
            .onAppear {
                loadGoal()
            }
        }
    }
    
    func saveGoal() {
        UserDefaults.standard.set(eventName, forKey: "goal_name")
        UserDefaults.standard.set(eventDate, forKey: "goal_date")
    }
    
    func loadGoal() {
        if let name = UserDefaults.standard.string(forKey: "goal_name") {
            eventName = name
        }
        if let date = UserDefaults.standard.object(forKey: "goal_date") as? Date {
            eventDate = date
        }
    }
    
    func clearGoal() {
        UserDefaults.standard.removeObject(forKey: "goal_name")
        UserDefaults.standard.removeObject(forKey: "goal_date")
    }
}
