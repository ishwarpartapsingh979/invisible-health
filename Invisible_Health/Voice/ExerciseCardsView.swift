import SwiftUI
import UIKit

/// One exercise as sent by the agent over the "exercises" data channel topic.
struct ExerciseItem: Codable, Identifiable, Hashable {
    var id = UUID()
    let name: String?
    let equipment: String?
    let level: String?
    let images: [String]

    private enum CodingKeys: String, CodingKey { case name, equipment, level, images }

    var imageURLs: [URL] { images.compactMap { URL(string: $0) } }
}

/// Full-screen, swipeable deck of exercise demos shown over the Voice tab when
/// the user asks the coach to "show me <muscle> exercises". Tap ✕ to dismiss.
struct ExerciseCardsView: View {
    let muscle: String
    let items: [ExerciseItem]
    let onClose: () -> Void

    @State private var index = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Text("\(muscle.capitalized) exercises")
                        .font(.headline).foregroundColor(.white)
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 30))
                            .foregroundColor(.white.opacity(0.85))
                    }
                }
                .padding(.horizontal, 20).padding(.top, 12)

                TabView(selection: $index) {
                    ForEach(Array(items.enumerated()), id: \.offset) { i, ex in
                        ExerciseDemoCard(item: ex).tag(i)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                Text("\(index + 1) of \(items.count)  ·  swipe to browse")
                    .font(.caption).foregroundColor(.gray)
                    .padding(.bottom, 16)
            }
        }
    }
}

private struct ExerciseDemoCard: View {
    let item: ExerciseItem

    var body: some View {
        VStack(spacing: 16) {
            AnimatedImageView(urls: item.imageURLs)
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .padding(.horizontal, 24)

            VStack(spacing: 6) {
                Text(item.name ?? "Exercise")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                HStack(spacing: 8) {
                    if let eq = item.equipment, eq != "body only" {
                        tag(eq.capitalized, "dumbbell.fill")
                    } else {
                        tag("Bodyweight", "figure.strengthtraining.functional")
                    }
                    if let lvl = item.level { tag(lvl.capitalized, "chart.bar.fill") }
                }
            }
            .padding(.horizontal, 24)
            Spacer(minLength: 0)
        }
        .padding(.top, 16)
    }

    private func tag(_ text: String, _ icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Color.white.opacity(0.1))
            .foregroundColor(.white.opacity(0.9))
            .clipShape(Capsule())
    }
}

/// Downloads an exercise's start/end images and animates between them (the
/// "GIF") on-device — no GIF files or hosting needed.
struct AnimatedImageView: UIViewRepresentable {
    let urls: [URL]

    func makeUIView(context: Context) -> UIImageView {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.clipsToBounds = true
        load(into: iv)
        return iv
    }

    func updateUIView(_ uiView: UIImageView, context: Context) {}

    private func load(into iv: UIImageView) {
        let urls = self.urls
        Task {
            var imgs: [UIImage] = []
            for url in urls {
                if let (data, _) = try? await URLSession.shared.data(from: url),
                   let img = UIImage(data: data) {
                    imgs.append(img)
                }
            }
            await MainActor.run {
                if imgs.count >= 2 {
                    iv.animationImages = imgs
                    iv.animationDuration = 1.3   // ~0.65s per position
                    iv.animationRepeatCount = 0  // loop forever
                    iv.image = imgs.first
                    iv.startAnimating()
                } else {
                    iv.image = imgs.first
                }
            }
        }
    }
}
