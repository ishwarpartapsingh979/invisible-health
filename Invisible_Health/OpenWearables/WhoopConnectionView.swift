//
//  WhoopConnectionView.swift
//  Invisible_Health
//
//  UI for setting up the Open Wearables backend and connecting Whoop.
//

import SwiftUI

struct WhoopConnectionView: View {
    @StateObject private var openWearables = OpenWearablesManager.shared
    @StateObject private var healthManager = HealthManager.shared
    @State private var showingSetupSheet = false
    @State private var showingDisconnectAlert = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    headerSection
                    configurationCard
                    connectionStatusCard

                    if openWearables.isWhoopConnected {
                        quickStatsSection
                        syncSection
                    }

                    actionButton
                    dataSourcesSection

                    Spacer(minLength: 50)
                }
                .padding()
            }
            .navigationTitle("Connected Devices")
            .navigationBarTitleDisplayMode(.large)
        }
        .alert("Disconnect Whoop?", isPresented: $showingDisconnectAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Disconnect", role: .destructive) {
                openWearables.disconnect()
            }
        } message: {
            Text("This will clear stored credentials and stop syncing Whoop data.")
        }
        .sheet(isPresented: $showingSetupSheet) {
            OpenWearablesSetupView()
        }
        .onAppear {
            if openWearables.isConfigured {
                openWearables.checkConnectionStatus()
            }
        }
    }

    // MARK: - Header
    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "applewatch.and.arrow.forward.circle")
                .font(.system(size: 50))
                .foregroundColor(.blue)
                .symbolRenderingMode(.hierarchical)

            Text("Unified Health Data")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Connect your devices to get comprehensive health insights")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding(.vertical)
    }

    // MARK: - Configuration card
    private var configurationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: openWearables.isConfigured ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundColor(openWearables.isConfigured ? .green : .orange)
                Text("Open Wearables")
                    .font(.headline)
                Spacer()
                Button(openWearables.isConfigured ? "Edit" : "Set up") {
                    showingSetupSheet = true
                }
                .font(.subheadline)
            }
            Text(openWearables.isConfigured
                 ? "API key and user ID configured."
                 : "Add your Open Wearables API key and user ID before connecting any providers.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    // MARK: - Connection status
    private var connectionStatusCard: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "circle.hexagongrid.circle.fill")
                    .font(.title)
                    .foregroundColor(openWearables.isWhoopConnected ? .green : .gray)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Whoop 4.0")
                        .font(.headline)
                    Text(openWearables.isWhoopConnected ? "Connected" : "Not Connected")
                        .font(.caption)
                        .foregroundColor(openWearables.isWhoopConnected ? .green : .secondary)
                }
                Spacer()
                if openWearables.isSyncing {
                    ProgressView().scaleEffect(0.8)
                }
            }

            if let lastSync = openWearables.lastSyncDate {
                HStack {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Last synced \(lastSync, style: .relative) ago")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }

            if let error = openWearables.syncError {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.orange)
                    Spacer()
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    // MARK: - Quick stats
    private var quickStatsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Today's Metrics")
                .font(.headline)
                .padding(.horizontal, 4)

            HStack(spacing: 12) {
                WhoopMetricCard(
                    title: "Recovery",
                    value: openWearables.whoopRecovery?.recoveryScore?.formatted() ?? "--",
                    unit: "%",
                    color: colorForRecovery(openWearables.whoopRecovery?.recoveryScore ?? 0),
                    icon: "heart.circle.fill"
                )

                WhoopMetricCard(
                    title: "Strain",
                    value: openWearables.whoopStrain?.dayStrain?.formatted() ?? "--",
                    unit: "",
                    color: .orange,
                    icon: "flame.fill"
                )

                WhoopMetricCard(
                    title: "Sleep",
                    value: openWearables.whoopSleep?.sleepPerformancePercentage?.formatted() ?? "--",
                    unit: "%",
                    color: .indigo,
                    icon: "moon.fill"
                )
            }

            if let whoopHRV = openWearables.whoopRecovery?.hrvMillis,
               let appleHRV = healthManager.cachedMorningAudit?.dailyBaseline.hrv {
                ComparisonCard(
                    title: "HRV Comparison",
                    appleValue: appleHRV,
                    whoopValue: whoopHRV,
                    unit: "ms",
                    higherIsBetter: true
                )
            }
        }
    }

    // MARK: - Sync section
    private var syncSection: some View {
        HStack {
            Button(action: {
                openWearables.triggerProviderSync()
                openWearables.performSync()
            }) {
                Label("Sync Now", systemImage: "arrow.clockwise")
                    .font(.subheadline)
            }
            .buttonStyle(.bordered)
            .disabled(openWearables.isSyncing)

            Spacer()

            Text("Auto-sync every \(OpenWearablesConfig.syncIntervalMinutes) min")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Action button
    private var actionButton: some View {
        Group {
            if openWearables.isWhoopConnected {
                Button(action: { showingDisconnectAlert = true }) {
                    Label("Disconnect", systemImage: "minus.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            } else {
                Button(action: { openWearables.connectWhoop() }) {
                    Label("Connect Whoop", systemImage: "plus.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!openWearables.isConfigured)
            }
        }
        .controlSize(.large)
    }

    // MARK: - Data sources
    private var dataSourcesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Data Sources")
                .font(.headline)
                .padding(.horizontal, 4)

            DataSourceRow(
                name: "Apple Health",
                icon: "heart.fill",
                color: .red,
                isConnected: true,
                metrics: ["Steps", "Workouts", "Heart Rate", "Sleep", "CGM"]
            )

            DataSourceRow(
                name: "Whoop 4.0",
                icon: "waveform.path.ecg",
                color: .purple,
                isConnected: openWearables.isWhoopConnected,
                metrics: ["Recovery", "Strain", "Sleep Coach", "HRV"]
            )

            DataSourceRow(
                name: "Libre 2 CGM",
                icon: "chart.line.uptrend.xyaxis",
                color: .orange,
                isConnected: false,
                metrics: ["Glucose", "Trends", "Time in Range"],
                note: "Via Apple Health"
            )
        }
        .padding(.vertical)
    }

    private func colorForRecovery(_ score: Double) -> Color {
        switch score {
        case 67...100: return .green
        case 34...66: return .yellow
        default: return .red
        }
    }
}

// MARK: - Setup sheet
struct OpenWearablesSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var manager = OpenWearablesManager.shared
    @State private var apiKey: String = ""
    @State private var userId: String = ""

    var body: some View {
        NavigationView {
            Form {
                Section {
                    SecureField("paste API key", text: $apiKey)
                        .textContentType(.password)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                } header: {
                    Text("API Key")
                } footer: {
                    Text("From Open Wearables → Settings → Credentials → Create API Key.")
                }

                Section {
                    TextField("user UUID", text: $userId)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                } header: {
                    Text("User ID")
                } footer: {
                    Text("From Open Wearables → Users → your user. Copy the UUID from the URL or User ID field.")
                }

                Section {
                    Text("Base URL")
                        .font(.caption)
                    Text(OpenWearablesConfig.baseURL)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Open Wearables Setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        manager.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                        manager.userId = userId.trimmingCharacters(in: .whitespacesAndNewlines)
                        manager.checkConnectionStatus()
                        dismiss()
                    }
                    .disabled(apiKey.trimmingCharacters(in: .whitespaces).isEmpty
                              || userId.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                apiKey = manager.apiKey ?? ""
                userId = manager.userId ?? ""
            }
        }
    }
}

// MARK: - Supporting views (unchanged)
struct WhoopMetricCard: View {
    let title: String
    let value: String
    let unit: String
    let color: Color
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(color)
                Spacer()
            }
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(color)
                Text(unit)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct ComparisonCard: View {
    let title: String
    let appleValue: Double
    let whoopValue: Double
    let unit: String
    let higherIsBetter: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
            HStack {
                VStack(alignment: .leading) {
                    Label("Apple", systemImage: "applelogo")
                        .font(.caption)
                    Text("\(Int(appleValue)) \(unit)")
                        .font(.headline)
                }
                Spacer()
                Image(systemName: "arrow.left.arrow.right")
                    .foregroundColor(.secondary)
                Spacer()
                VStack(alignment: .trailing) {
                    Label("Whoop", systemImage: "waveform.path.ecg")
                        .font(.caption)
                    Text("\(Int(whoopValue)) \(unit)")
                        .font(.headline)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct DataSourceRow: View {
    let name: String
    let icon: String
    let color: Color
    let isConnected: Bool
    let metrics: [String]
    var note: String? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(isConnected ? color : .gray)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    if isConnected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
                Text(metrics.joined(separator: " • "))
                    .font(.caption)
                    .foregroundColor(.secondary)
                if let note = note {
                    Text(note)
                        .font(.caption2)
                        .foregroundColor(.blue)
                }
            }
            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(.systemGray6))
        .cornerRadius(10)
        .opacity(isConnected ? 1 : 0.6)
    }
}

struct WhoopConnectionView_Previews: PreviewProvider {
    static var previews: some View {
        WhoopConnectionView()
    }
}
