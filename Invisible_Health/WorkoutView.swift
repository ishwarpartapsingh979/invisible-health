import SwiftUI
import HealthKit

struct WorkoutView: View {
    @State private var workouts: [HKWorkout] = []
    
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
                    Button(action: { fetchWorkouts() }) {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(.orange)
                    }
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
        case .yoga: return "figure.yoga"
        case .cycling: return "bicycle"
        case .swimming: return "figure.pool.swim"
        case .highIntensityIntervalTraining: return "figure.cross.training"
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
        default: return "Workout"
        }
    }
}
