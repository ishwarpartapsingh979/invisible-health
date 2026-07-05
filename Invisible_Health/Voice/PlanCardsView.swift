import SwiftUI

/// One of today's plan options, sent by the coach over the "plans" data channel.
struct CoachPlan: Codable, Identifiable, Hashable {
    var id = UUID()
    let title: String
    let detail: String
    let kind: String   // "preferred" | "dad" | "readiness"

    private enum CodingKeys: String, CodingKey { case title, detail, kind }

    var badge: (String, String) {
        switch kind {
        case "dad": return ("Dad's pick", "person.wave.2.fill")
        case "readiness": return ("Readiness-smart", "heart.text.square.fill")
        default: return ("Your pick", "star.fill")
        }
    }
}

/// Full-screen chooser for today's 3 plans. Tap one to start the workout with it.
struct PlanCardsView: View {
    let plans: [CoachPlan]
    let onSelect: (CoachPlan) -> Void
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Text("Today's plan").font(.headline).foregroundColor(.white)
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28)).foregroundColor(.white.opacity(0.85))
                    }
                }
                .padding(.horizontal, 20).padding(.top, 14)

                ScrollView {
                    VStack(spacing: 14) {
                        ForEach(plans) { plan in
                            Button { onSelect(plan) } label: { card(plan) }
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(20)
                }
                Text("Pick one to start — or just keep talking to the coach.")
                    .font(.caption).foregroundColor(.gray).padding(.bottom, 16)
            }
        }
    }

    private func card(_ plan: CoachPlan) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(plan.badge.0, systemImage: plan.badge.1)
                .font(.caption.weight(.semibold))
                .foregroundColor(.white.opacity(0.9))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Color.white.opacity(0.12)).clipShape(Capsule())
            Text(plan.title)
                .font(.title3.weight(.semibold)).foregroundColor(.white)
            Text(plan.detail)
                .font(.subheadline).foregroundColor(.white.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Text("Start this").font(.subheadline.weight(.semibold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Color.white).clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}
