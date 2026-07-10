import SwiftUI

// MARK: - Model (mirrors the agent's "nutrition_summary" data-channel payload)

struct NutritionSummary: Codable {
    var total: Int
    var proteinHits: Int
    var flagged: Int
    var days: [Day]
    var watch: [Watch]
    var questions: [String]
    var empty: Bool

    struct Day: Codable, Identifiable {
        var day: String
        var items: [String]
        var id: String { day }
    }
    struct Watch: Codable, Identifiable {
        var desc: String
        var issues: String
        var id: String { desc + issues }
    }

    enum CodingKeys: String, CodingKey {
        case total, flagged, days, watch, questions, empty
        case proteinHits = "protein_hits"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        total       = try c.decodeIfPresent(Int.self, forKey: .total) ?? 0
        proteinHits = try c.decodeIfPresent(Int.self, forKey: .proteinHits) ?? 0
        flagged     = try c.decodeIfPresent(Int.self, forKey: .flagged) ?? 0
        days        = try c.decodeIfPresent([Day].self, forKey: .days) ?? []
        watch       = try c.decodeIfPresent([Watch].self, forKey: .watch) ?? []
        questions   = try c.decodeIfPresent([String].self, forKey: .questions) ?? []
        empty       = try c.decodeIfPresent(Bool.self, forKey: .empty) ?? (total == 0)
    }

    // Local cache so the tab shows the last summary even before reconnecting.
    private static let cacheKey = "nutrition_summary_cache"
    private static let stampKey = "nutrition_summary_updated"

    static var cached: NutritionSummary? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else { return nil }
        return try? JSONDecoder().decode(NutritionSummary.self, from: data)
    }
    static var lastUpdated: Date? {
        UserDefaults.standard.object(forKey: stampKey) as? Date
    }
    func cache() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.cacheKey)
            UserDefaults.standard.set(Date(), forKey: Self.stampKey)
        }
    }
}

// Encodable side (for caching only — keeps snake_case symmetry).
extension NutritionSummary {
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(total, forKey: .total)
        try c.encode(proteinHits, forKey: .proteinHits)
        try c.encode(flagged, forKey: .flagged)
        try c.encode(days, forKey: .days)
        try c.encode(watch, forKey: .watch)
        try c.encode(questions, forKey: .questions)
        try c.encode(empty, forKey: .empty)
    }
}

// MARK: - View

struct NutritionTabView: View {
    @ObservedObject var call: VoiceCallManager
    @Binding var selectedTab: Int
    @Binding var pendingVoiceAction: String?

    @State private var summary: NutritionSummary? = NutritionSummary.cached
    @State private var updated: Date? = NutritionSummary.lastUpdated
    @State private var refreshing = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Text("NUTRITION")
                    .font(.caption).tracking(2).foregroundColor(.gray).padding(.top, 12)

                if let s = summary, !s.empty, s.total > 0 {
                    statsCard(s)
                    if !s.days.isEmpty { daysCard(s) }
                    if !s.watch.isEmpty { watchCard(s) }
                    if !s.questions.isEmpty { questionsCard(s) }
                } else {
                    emptyState
                }

                refreshButton
                if let u = updated {
                    Text("Updated \(u.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption2).foregroundColor(.gray.opacity(0.7))
                }
                Spacer(minLength: 12)
            }
            .padding(.horizontal, 24)
        }
        .onAppear {
            call.onNutritionSummary = { s in
                s.cache()
                self.summary = s
                self.updated = NutritionSummary.lastUpdated
                self.refreshing = false
            }
        }
    }

    // MARK: cards

    private func statsCard(_ s: NutritionSummary) -> some View {
        HStack(spacing: 0) {
            stat("\(s.total)", "meals logged")
            divider
            stat("\(s.proteinHits)/\(s.total)", "with protein")
            divider
            stat("\(s.flagged)", "to watch")
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.title2.weight(.bold)).foregroundColor(.white)
            Text(label).font(.caption2).foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1, height: 34)
    }

    private func daysCard(_ s: NutritionSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("THIS WEEK")
            ForEach(s.days) { d in
                VStack(alignment: .leading, spacing: 2) {
                    Text(d.day).font(.subheadline.weight(.semibold)).foregroundColor(.white)
                    Text(d.items.joined(separator: " · "))
                        .font(.caption).foregroundColor(.gray)
                }
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func watchCard(_ s: NutritionSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("TO WATCH")
            ForEach(s.watch) { w in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2).foregroundColor(.orange).padding(.top, 2)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(w.desc).font(.subheadline).foregroundColor(.white)
                        Text(w.issues).font(.caption).foregroundColor(.orange.opacity(0.85))
                    }
                }
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func questionsCard(_ s: NutritionSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("ASK YOUR NUTRITIONIST")
            ForEach(Array(s.questions.enumerated()), id: \.offset) { i, q in
                HStack(alignment: .top, spacing: 8) {
                    Text("\(i + 1).").font(.caption.weight(.bold)).foregroundColor(.blue)
                    Text(q).font(.caption).foregroundColor(.gray)
                }
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func sectionTitle(_ t: String) -> some View {
        Text(t).font(.caption2).tracking(1.5).foregroundColor(.gray)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "fork.knife").font(.system(size: 48)).foregroundColor(.gray)
            Text("No meals logged yet this week")
                .font(.headline).foregroundColor(.white)
            Text("Just tell your coach what you eat as you go — “had eggs and toast”, “about to order a pizza”. It builds up here for your nutritionist.")
                .font(.caption).foregroundColor(.gray)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 30).frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var refreshButton: some View {
        Button {
            refreshing = true
            if call.state == .connected {
                Task { await call.sendGetNutritionSummary() }
            } else {
                // Connect via the Voice tab, then auto-refresh.
                pendingVoiceAction = "nutrition_refresh"
                selectedTab = 17
            }
        } label: {
            Label(refreshing ? "Refreshing…" : "Refresh via coach", systemImage: "arrow.clockwise")
                .font(.headline).frame(maxWidth: .infinity).padding()
                .background(Color.blue.opacity(0.18))
                .foregroundColor(.blue).clipShape(Capsule())
        }
        .disabled(refreshing)
    }
}
