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

/// The decided workout + planning discussion, read from the DB (planned_workouts)
/// via the token server — so the tab reflects what was actually decided/discussed,
/// no voice session needed. Mirrors the /workout endpoint.
struct WorkoutPlanDB: Codable {
    var decided: String?
    var discussion: String?
    var suggested: String?
    var status: String?
}

/// The Workout Plan tab (like the Whoop tab): today's decided workout + the
/// planning conversation, with two actions — DISCUSS (decide it, by voice) and
/// START (do it).
struct PlanTabView: View {
    @ObservedObject var workout: WorkoutSessionController
    @Binding var selectedTab: Int
    /// Handed to the Voice tab so it performs the action on appear.
    @Binding var pendingVoiceAction: String?

    @State private var plan: WorkoutPlanDB?
    /// Local fallback (set instantly when the coach confirms a label this session).
    @State private var localDecided = PlannedWorkout.today?.decided
    @State private var loading = false

    private var decided: String? { plan?.decided ?? localDecided }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Text("WORKOUT PLAN")
                    .font(.caption).tracking(2).foregroundColor(.gray).padding(.top, 12)

                // The decided workout, or a prompt to decide one.
                VStack(spacing: 8) {
                    Image(systemName: decided == nil ? "questionmark.circle" : "figure.run.circle.fill")
                        .font(.system(size: 56))
                        .foregroundColor(decided == nil ? .gray : .blue)
                    Text(decided ?? "Not decided yet")
                        .font(.title2.weight(.semibold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                    if decided == nil {
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

                // The planning conversation that led to the decision.
                if let d = plan?.discussion, !d.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("HOW YOU DECIDED IT")
                            .font(.caption2).tracking(1.5).foregroundColor(.gray)
                        Text(d)
                            .font(.caption).foregroundColor(.gray)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .padding(.horizontal, 24)
                }

                Button { Task { await refresh() } } label: {
                    Label(loading ? "Refreshing…" : "Refresh", systemImage: "arrow.clockwise")
                        .font(.subheadline).foregroundColor(.gray)
                }
                .disabled(loading)

                Spacer(minLength: 12)
            }
        }
        .onAppear {
            localDecided = PlannedWorkout.today?.decided
            Task { await refresh() }
        }
    }

    /// Read the decided workout + discussion from the DB (via the token server).
    private func refresh() async {
        guard let url = URL(string: VoiceConfig.tokenServerBaseURL + "/workout?user_id=ishwar")
        else { return }
        loading = true
        defer { loading = false }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            plan = try JSONDecoder().decode(WorkoutPlanDB.self, from: data)
        } catch {
            // Keep the local fallback.
        }
    }
}
