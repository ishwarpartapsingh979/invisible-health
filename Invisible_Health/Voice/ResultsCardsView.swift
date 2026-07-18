import SwiftUI

// MARK: - Model (mirrors the agent's "results" data-channel payload)

/// One card in a results list (a place, a recipe, etc.).
struct AgentResult: Codable, Identifiable {
    var title: String
    var subtitle: String?
    var detail: String?
    var url: String?
    var action: String?          // e.g. "menu" → tap runs a follow-up ask
    var id: String { title + (subtitle ?? "") }
}

/// A published list the coach put on screen (kind = "places" | "recipes" | ...).
struct AgentResults: Codable {
    var kind: String?
    var title: String?
    var items: [AgentResult]
}

// MARK: - View

/// A lightweight scrollable card list — restaurants near you, meal ideas, etc.
/// The coach speaks a one-line summary; the details render here.
struct ResultsCardsView: View {
    let results: AgentResults
    /// Fired when a card's action button is tapped (e.g. "See menu").
    var onAction: (AgentResult) -> Void
    var onClose: () -> Void

    private var isRecipes: Bool { results.kind == "recipes" }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(results.items) { item in
                        card(item)
                    }
                }
                .padding(16)
            }
            .navigationTitle(results.title ?? (isRecipes ? "Meal ideas" : "Results"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onClose() }
                }
            }
        }
    }

    private func card(_ item: AgentResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.title).font(.headline)
            if let s = item.subtitle, !s.isEmpty {
                Text(s).font(.subheadline).foregroundColor(.secondary)
            }
            if let d = item.detail, !d.isEmpty {
                Text(d).font(.caption).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 18) {
                if let u = item.url, !u.isEmpty, let url = URL(string: u) {
                    Link(destination: url) {
                        Label(isRecipes ? "Watch" : "Open in Maps",
                              systemImage: isRecipes ? "play.circle" : "map")
                            .font(.caption.weight(.semibold))
                    }
                }
                if item.action == "menu" {
                    Button { onAction(item) } label: {
                        Label("See menu", systemImage: "fork.knife")
                            .font(.caption.weight(.semibold))
                    }
                }
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
