import SwiftUI
import UIKit

/// The user's onboarding profile (Tier 3 #11). Stored locally (UserDefaults) and
/// streamed to the coach so it can tailor advice + generate today's plans.
struct UserProfile: Codable {
    var goal: String = ""
    var preferred: String = ""
    var level: String = ""
    var daysPerWeek: Int = 3
    var equipment: String = ""
    var injuries: String = ""
    /// Music service linked at onboarding ("apple_music" | "spotify" | ""), so the
    /// immersive workout experience can drive it. Tolerant default keeps old saved
    /// profiles decodable.
    var musicService: String = ""

    static let key = "user_profile_v1"

    static var saved: UserProfile? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let p = try? JSONDecoder().decode(UserProfile.self, from: data) else { return nil }
        return p
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    /// Payload sent to the coach over the "profile" data channel.
    var dictionary: [String: Any] {
        ["goal": goal, "preferred": preferred, "level": level,
         "days_per_week": daysPerWeek, "equipment": equipment, "injuries": injuries,
         "music_service": musicService]
    }
}

/// Entry to onboarding — VOICE FIRST. Primary: talk to the coach (it interviews
/// you). Secondary: type it in. Reused for first-run and "Edit profile".
struct OnboardingChoiceView: View {
    /// Start the voice interview (connect + tell the coach to onboard).
    let onVoice: () -> Void
    /// Save from the text form.
    let onTextSaved: (UserProfile) -> Void

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                Spacer()
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 64)).foregroundColor(.blue)
                Text("Set up your coach")
                    .font(.title2.weight(.semibold))
                Text("Just talk — your coach will ask a few quick questions and set everything up.")
                    .font(.subheadline).foregroundColor(.secondary)
                    .multilineTextAlignment(.center).padding(.horizontal, 32)

                // Show the current profile if one exists (so you can SEE it).
                if let p = UserProfile.saved, !p.goal.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("YOUR PROFILE").font(.caption).foregroundColor(.secondary)
                        profileRow("Goal", p.goal)
                        profileRow("Prefers", p.preferred)
                        profileRow("Level", p.level)
                        profileRow("Days/week", "\(p.daysPerWeek)")
                        profileRow("Equipment", p.equipment)
                        if !p.injuries.isEmpty { profileRow("Injuries", p.injuries) }
                    }
                    .padding().frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(UIColor.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal, 24)
                }

                Button(action: onVoice) {
                    Label("Talk to set up", systemImage: "mic.fill")
                        .font(.headline).frame(maxWidth: .infinity)
                        .padding().background(Color.blue)
                        .foregroundColor(.white).clipShape(Capsule())
                }
                .padding(.horizontal, 32)

                NavigationLink {
                    OnboardingView(profile: UserProfile.saved ?? UserProfile(), onDone: onTextSaved)
                } label: {
                    Text(UserProfile.saved == nil ? "Type it instead" : "Edit by typing")
                        .font(.subheadline).foregroundColor(.secondary)
                }
                Spacer()
            }
        }
    }

    private func profileRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundColor(.secondary)
            Spacer()
            Text(value.isEmpty ? "—" : value).foregroundColor(.primary)
        }
        .font(.subheadline)
    }
}

/// The text-entry onboarding form (the secondary path). Also reachable to edit.
struct OnboardingView: View {
    @State var profile: UserProfile
    let onDone: (UserProfile) -> Void

    private let goals = ["Weight loss", "Endurance", "Strength", "General fitness"]
    private let preferreds = ["Gym strength", "Running", "Dance fitness", "Mixed"]
    private let levels = ["Beginner", "Intermediate", "Advanced"]
    private let equip = ["Full gym", "Home weights", "Bodyweight only", "Outdoor / running"]

    var body: some View {
        NavigationView {
            Form {
                Section("Your goal") {
                    Picker("Primary goal", selection: $profile.goal) {
                        Text("Choose").tag("")
                        ForEach(goals, id: \.self) { Text($0).tag($0) }
                    }
                }
                Section("How you like to train") {
                    Picker("Preferred", selection: $profile.preferred) {
                        Text("Choose").tag("")
                        ForEach(preferreds, id: \.self) { Text($0).tag($0) }
                    }
                    Picker("Experience", selection: $profile.level) {
                        Text("Choose").tag("")
                        ForEach(levels, id: \.self) { Text($0).tag($0) }
                    }
                    Stepper("Days per week: \(profile.daysPerWeek)",
                            value: $profile.daysPerWeek, in: 1...7)
                    Picker("Equipment", selection: $profile.equipment) {
                        Text("Choose").tag("")
                        ForEach(equip, id: \.self) { Text($0).tag($0) }
                    }
                }
                Section("Injuries or limits (optional)") {
                    TextField("e.g. sensitive right hamstring", text: $profile.injuries,
                              axis: .vertical)
                }
                Section("Music (optional)") {
                    MusicConnectView { service in
                        profile.musicService = service.rawValue
                    }
                }
                Section {
                    Button("Save") {
                        profile.save()
                        onDone(profile)
                    }
                    .disabled(profile.goal.isEmpty || profile.preferred.isEmpty)
                }
            }
            .navigationTitle("Set up your coach")
        }
    }
}
