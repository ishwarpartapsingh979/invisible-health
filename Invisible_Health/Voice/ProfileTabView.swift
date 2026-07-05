import SwiftUI

/// The Profile tab (its own tab, like Voice/Whoop): shows the saved profile and
/// lets you set it up / edit it — voice-first.
struct ProfileTabView: View {
    @ObservedObject var call: VoiceCallManager
    @Binding var selectedTab: Int
    @Binding var pendingVoiceAction: String?

    @State private var profile = UserProfile.saved
    @State private var showTextForm = false

    var body: some View {
        VStack(spacing: 20) {
            Text("YOUR PROFILE")
                .font(.caption).tracking(2).foregroundColor(.gray).padding(.top, 12)

            if let p = profile, !p.goal.isEmpty {
                VStack(spacing: 10) {
                    row("Goal", p.goal)
                    row("Prefers", p.preferred)
                    row("Level", p.level)
                    row("Days / week", "\(p.daysPerWeek)")
                    row("Equipment", p.equipment)
                    if !p.injuries.isEmpty { row("Injuries", p.injuries) }
                }
                .padding().background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .padding(.horizontal, 24)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.system(size: 52)).foregroundColor(.gray)
                    Text("No profile yet")
                        .font(.title3.weight(.semibold)).foregroundColor(.white)
                    Text("Set it up so your coach can tailor everything to you.")
                        .font(.subheadline).foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                }
                .padding(.vertical, 24)
            }

            // Voice-first: talk to set up / update.
            Button {
                pendingVoiceAction = "onboard"
                selectedTab = 17
            } label: {
                Label(profile == nil ? "Talk to set up" : "Update by voice", systemImage: "mic.fill")
                    .font(.headline).frame(maxWidth: .infinity).padding()
                    .background(Color.blue).foregroundColor(.white).clipShape(Capsule())
            }
            .padding(.horizontal, 24)

            Button("Edit by typing") { showTextForm = true }
                .font(.subheadline).foregroundColor(.secondary)

            Spacer()
        }
        .onAppear { profile = UserProfile.saved }
        .sheet(isPresented: $showTextForm) {
            OnboardingView(profile: UserProfile.saved ?? UserProfile()) { p in
                showTextForm = false
                profile = p
                Task { await call.sendProfile(p.dictionary) }
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundColor(.gray)
            Spacer()
            Text(value.isEmpty ? "—" : value).foregroundColor(.white)
        }
        .font(.subheadline)
    }
}
