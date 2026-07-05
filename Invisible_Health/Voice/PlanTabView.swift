import SwiftUI

/// The workout DECIDED for today (locally cached; set when the coach confirms a
/// plan via set_workout_label, or when you tap a plan card).
struct PlannedWorkout: Codable {
    var decided: String
    var savedAt: Date

    static let key = "planned_workout_v1"

    static var today: PlannedWorkout? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let p = try? JSONDecoder().decode(PlannedWorkout.self, from: data) else { return nil }
        // Only surface it if it was decided today.
        return Calendar.current.isDateInToday(p.savedAt) ? p : nil
    }

    static func save(_ decided: String) {
        let p = PlannedWorkout(decided: decided, savedAt: Date())
        if let data = try? JSONEncoder().encode(p) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

/// The Plan tab (like the Whoop tab): shows today's decided workout, with two
/// clear actions — DISCUSS (decide it, by voice) and START (do it).
struct PlanTabView: View {
    @ObservedObject var workout: WorkoutSessionController
    @Binding var selectedTab: Int
    /// Handed to the Voice tab so it performs the action on appear.
    @Binding var pendingVoiceAction: String?

    @State private var planned = PlannedWorkout.today

    var body: some View {
        VStack(spacing: 22) {
            Text("TODAY'S WORKOUT")
                .font(.caption).tracking(2).foregroundColor(.gray)

            // The decided workout, or a prompt to decide one.
            VStack(spacing: 8) {
                Image(systemName: planned == nil ? "questionmark.circle" : "figure.run.circle.fill")
                    .font(.system(size: 56))
                    .foregroundColor(planned == nil ? .gray : .blue)
                Text(planned?.decided ?? "Not decided yet")
                    .font(.title2.weight(.semibold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                if planned == nil {
                    Text("Discuss with your coach to decide today's plan.")
                        .font(.subheadline).foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .padding(.horizontal, 24)

            // Two actions: decide it (voice) vs do it.
            VStack(spacing: 12) {
                Button {
                    pendingVoiceAction = "discuss"
                    selectedTab = 17               // go to the Voice tab to talk
                } label: {
                    Label("Discuss Workout", systemImage: "bubble.left.and.bubble.right.fill")
                        .font(.headline).frame(maxWidth: .infinity).padding()
                        .background(Color.white.opacity(0.12))
                        .foregroundColor(.white).clipShape(Capsule())
                }
                Button {
                    pendingVoiceAction = "start"
                    selectedTab = 17
                } label: {
                    Label("Start Workout", systemImage: "play.fill")
                        .font(.headline).frame(maxWidth: .infinity).padding()
                        .background(Color.green.opacity(0.22))
                        .foregroundColor(.green).clipShape(Capsule())
                }
            }
            .padding(.horizontal, 24)

            Spacer()
        }
        .padding(.top, 12)
        .onAppear { planned = PlannedWorkout.today }
    }
}
