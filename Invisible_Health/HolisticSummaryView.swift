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
            // Make sure Whoop data is fresh before asking Gemini for a read,
            // otherwise the summary fires with stale/empty Whoop fields and
            // the user has to manually hit Sync Now in Devices first.
            if openWearables.isConfigured && openWearables.isWhoopConnected {
                openWearables.triggerProviderSync()
                openWearables.performSync()
            }
            if summaryText == nil { refresh() }
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
        return HStack(spacing: 10) {
            SignalChip(label: "Recovery", value: r?.recoveryScore.map { "\(Int($0))%" } ?? "--", tint: .green)
            SignalChip(label: "Sleep Eff", value: s?.efficiencyPercent.map { "\(Int($0))%" } ?? "--", tint: .indigo)
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
        let attributed = (try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)

        return Text(attributed)
            .font(.body)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
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
