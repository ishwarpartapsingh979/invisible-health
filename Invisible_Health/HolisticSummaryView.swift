//
//  HolisticSummaryView.swift
//  Invisible_Health
//
//  Top-level "state of body + what to do today" view.
//  Sends Apple Health + Whoop signals to backend (action=holistic_summary)
//  which calls Gemini Pro and returns a markdown read.
//

import SwiftUI

struct HolisticSummaryView: View {
    @StateObject private var agent = AgentManager.shared
    @StateObject private var openWearables = OpenWearablesManager.shared

    @State private var summaryText: String?
    @State private var lastUpdated: Date?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                signalStrip

                if isLoading && summaryText == nil {
                    loadingPlaceholder
                } else if let error = errorMessage, summaryText == nil {
                    errorView(error)
                } else if let text = summaryText {
                    summaryBody(text)
                } else {
                    emptyState
                }

                Spacer(minLength: 40)
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
        }
        .background(Color.black.edgesIgnoringSafeArea(.all))
        .onAppear {
            guard summaryText == nil else { return }
            // Cold-launch path: refresh Whoop data first, THEN ask Gemini.
            // performSync's completion fires once all three Whoop fetches
            // return, so the summary call sees populated chips.
            if openWearables.isConfigured && openWearables.isWhoopConnected {
                isLoading = true
                openWearables.triggerProviderSync()
                openWearables.performSync {
                    refresh()
                }
            } else {
                // No Whoop configured — skip straight to Gemini with Apple-only data.
                refresh()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("STATE OF BODY")
                .font(.caption)
                .fontWeight(.semibold)
                .tracking(2)
                .foregroundColor(.gray)

            HStack(alignment: .firstTextBaseline) {
                Text("Today")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                Spacer()

                Button(action: refresh) {
                    Image(systemName: isLoading ? "hourglass" : "arrow.clockwise")
                        .font(.title3)
                        .foregroundColor(.white)
                        .padding(10)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Circle())
                }
                .disabled(isLoading)
            }

            if let lastUpdated = lastUpdated {
                Text("Updated \(lastUpdated, style: .relative) ago")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
    }

    private var signalStrip: some View {
        let r = openWearables.whoopRecovery
        let s = openWearables.whoopSleep
        // Sleep chip: show duration in hours (e.g. "3.6h") — more immediately
        // legible than "efficiency %" and avoids confusion with Whoop's
        // "Sleep %" (which is sleep performance vs. sleep need, a different metric).
        let sleepHoursText: String = {
            guard let mins = s?.durationMinutes, mins > 0 else { return "--" }
            return String(format: "%.1fh", mins / 60.0)
        }()
        return HStack(spacing: 10) {
            SignalChip(label: "Recovery", value: r?.recoveryScore.map { "\(Int($0))%" } ?? "--", tint: .green)
            SignalChip(label: "Sleep", value: sleepHoursText, tint: .indigo)
            SignalChip(label: "HRV", value: r?.avgHrvSdnnMs.map { "\(Int($0))" } ?? "--", tint: .blue)
            SignalChip(label: "RHR", value: r?.restingHeartRateBpm.map { "\(Int($0))" } ?? "--", tint: .orange)
        }
    }

    private var loadingPlaceholder: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(.white)
            Text("Gemini is reading your signals…")
                .font(.subheadline)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.title)
                .foregroundColor(.gray)
            Text("Tap refresh to generate today's read.")
                .font(.subheadline)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func errorView(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Couldn't generate summary", systemImage: "exclamationmark.triangle")
                .font(.subheadline)
                .foregroundColor(.orange)
            Text(message)
                .font(.caption)
                .foregroundColor(.gray)
            Button("Try again", action: refresh)
                .buttonStyle(.borderedProminent)
                .tint(.white.opacity(0.15))
                .foregroundColor(.white)
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
    }

    private func summaryBody(_ text: String) -> some View {
        // Defensive: handle any leftover literal "\n" escapes the backend may emit.
        let normalized = text.replacingOccurrences(of: "\\n", with: "\n")

        // Split into paragraphs (blank-line separated) so newlines actually render
        // as breaks. Each paragraph keeps inline markdown (**bold**, *italic*, etc.).
        let paragraphs = normalized
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                let attributed = (try? AttributedString(
                    markdown: paragraph,
                    options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
                )) ?? AttributedString(paragraph)

                Text(attributed)
                    .font(.body)
                    .foregroundColor(.white)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
        .background(Color.white.opacity(0.04))
        .cornerRadius(14)
    }

    // MARK: - Actions

    private func refresh() {
        isLoading = true
        errorMessage = nil
        agent.fetchHolisticSummary { result in
            isLoading = false
            switch result {
            case .success(let text):
                summaryText = text
                lastUpdated = Date()
            case .failure(let err):
                errorMessage = err.localizedDescription
            }
        }
    }
}

// MARK: - Shared chip used across Summary / Apple / Whoop views

struct SignalChip: View {
    let label: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.gray)
            Text(value)
                .font(.system(.title3, design: .rounded))
                .fontWeight(.semibold)
                .foregroundColor(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.white.opacity(0.05))
        .cornerRadius(10)
    }
}

struct HolisticSummaryView_Previews: PreviewProvider {
    static var previews: some View {
        HolisticSummaryView()
            .preferredColorScheme(.dark)
    }
}
