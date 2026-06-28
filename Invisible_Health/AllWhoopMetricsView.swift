//
//  AllWhoopMetricsView.swift
//  Invisible_Health
//
//  Raw dump of every Whoop metric we currently get from Open Wearables.
//  Recovery, Sleep, Strain, and connection diagnostics.
//

import SwiftUI

struct AllWhoopMetricsView: View {
    @StateObject private var openWearables = OpenWearablesManager.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                connectionSection
                recoverySection
                sleepSection
                strainSection
                workoutsSection

                Spacer(minLength: 40)
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
        }
        .background(Color.black.edgesIgnoringSafeArea(.all))
        .onAppear {
            if openWearables.isConfigured {
                openWearables.checkConnectionStatus()
                openWearables.performSync()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("WHOOP")
                .font(.caption)
                .fontWeight(.semibold)
                .tracking(2)
                .foregroundColor(.gray)
            HStack(alignment: .firstTextBaseline) {
                Text("All metrics")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                Spacer()
                Button(action: {
                    openWearables.triggerProviderSync()
                    openWearables.performSync()
                }) {
                    Image(systemName: openWearables.isSyncing ? "hourglass" : "arrow.clockwise")
                        .font(.title3)
                        .foregroundColor(.white)
                        .padding(10)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Circle())
                }
                .disabled(openWearables.isSyncing || !openWearables.isWhoopConnected)
            }
            if let lastSync = openWearables.lastSyncDate {
                Text("Last synced \(lastSync, style: .relative) ago")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
    }

    // MARK: - Sections

    private var connectionSection: some View {
        MetricGroup(title: "Connection") {
            MetricRow(label: "Configured (API key + user)", value: openWearables.isConfigured ? "Yes" : "No")
            MetricRow(label: "Whoop connected", value: openWearables.isWhoopConnected ? "Yes" : "No")
            MetricRow(label: "Auto-sync interval", value: "\(OpenWearablesConfig.syncIntervalMinutes) min")
            if let err = openWearables.syncError {
                MetricRow(label: "Last error", value: err)
            }
        }
    }

    private var recoverySection: some View {
        let r = openWearables.whoopRecovery
        return MetricGroup(title: "Recovery") {
            MetricRow(label: "Date", value: r?.date ?? "--")
            MetricRow(label: "Recovery Score", value: r?.recoveryScore.map { String(format: "%.0f%%", $0) } ?? "--")
            MetricRow(label: "Recovery Level", value: r?.recoveryLevel ?? "--")
            MetricRow(label: "HRV (SDNN)", value: r?.avgHrvSdnnMs.map { String(format: "%.1f ms", $0) } ?? "--")
            MetricRow(label: "Resting HR", value: r?.restingHeartRateBpm.map { "\(Int($0)) bpm" } ?? "--")
            MetricRow(label: "SpO₂", value: r?.avgSpo2Percent.map { String(format: "%.1f%%", $0) } ?? "--")
            MetricRow(label: "Sleep Duration (from recovery)", value: r?.sleepDurationSeconds.map { String(format: "%.1f h", $0 / 3600) } ?? "--")
            MetricRow(label: "Sleep Efficiency (from recovery)", value: r?.sleepEfficiencyPercent.map { String(format: "%.1f%%", $0) } ?? "--")
        }
    }

    private var sleepSection: some View {
        let s = openWearables.whoopSleep
        return MetricGroup(title: "Sleep") {
            MetricRow(label: "Date", value: s?.date ?? "--")
            MetricRow(label: "Start", value: s?.startTime ?? "--")
            MetricRow(label: "End", value: s?.endTime ?? "--")
            MetricRow(label: "Duration", value: s?.durationMinutes.map { "\(Int($0)) min" } ?? "--")
            MetricRow(label: "Time in Bed", value: s?.timeInBedMinutes.map { "\(Int($0)) min" } ?? "--")
            MetricRow(label: "Efficiency", value: s?.efficiencyPercent.map { String(format: "%.1f%%", $0) } ?? "--")
            MetricRow(label: "Awake", value: s?.stages?.awakeMinutes.map { "\(Int($0)) min" } ?? "--")
            MetricRow(label: "Light", value: s?.stages?.lightMinutes.map { "\(Int($0)) min" } ?? "--")
            MetricRow(label: "Deep (SWS)", value: s?.stages?.deepMinutes.map { "\(Int($0)) min" } ?? "--")
            MetricRow(label: "REM", value: s?.stages?.remMinutes.map { "\(Int($0)) min" } ?? "--")
            MetricRow(label: "Naps", value: s?.napCount.map { "\($0) (\(Int(s?.napDurationMinutes ?? 0)) min)" } ?? "--")
            MetricRow(label: "Interruptions", value: s?.interruptionsCount.map { "\($0)" } ?? "--")
            MetricRow(label: "Avg HR", value: s?.avgHeartRateBpm.map { "\(Int($0)) bpm" } ?? "--")
            MetricRow(label: "Avg HRV", value: s?.avgHrvSdnnMs.map { String(format: "%.1f ms", $0) } ?? "--")
            MetricRow(label: "Avg Respiratory Rate", value: s?.avgRespiratoryRate.map { String(format: "%.1f", $0) } ?? "--")
            MetricRow(label: "Avg SpO₂", value: s?.avgSpo2Percent.map { String(format: "%.1f%%", $0) } ?? "--")
        }
    }

    private var strainSection: some View {
        let st = openWearables.whoopStrain
        return MetricGroup(title: "Strain & Activity") {
            MetricRow(label: "Date", value: st?.date ?? "--")
            MetricRow(label: "Day Strain (0–21)", value: st?.dayStrain.map { String(format: "%.1f", $0) } ?? "--")
            MetricRow(label: "Strain Level", value: st?.strainLevel ?? "--")
            MetricRow(label: "Avg HR", value: st?.averageHeartRate.map { "\(Int($0)) bpm" } ?? "--")
            MetricRow(label: "Max HR", value: st?.maxHeartRate.map { "\(Int($0)) bpm" } ?? "--")
            MetricRow(label: "Energy", value: st?.kilojoules.map { String(format: "%.0f kJ (%.0f kcal)", $0, $0 * 0.239) } ?? "--")
            MetricRow(label: "Cardiovascular Load", value: st?.cardiovascularLoad.map { String(format: "%.1f", $0) } ?? "--")
            MetricRow(label: "Muscular Load", value: st?.muscularLoad.map { String(format: "%.1f", $0) } ?? "--")
            MetricRow(label: "Workouts (in range)", value: st?.workouts.map { "\($0.count)" } ?? "--")
        }
    }

    @ViewBuilder
    private var workoutsSection: some View {
        let workouts = openWearables.whoopStrain?.workouts ?? []
        ForEach(Array(workouts.enumerated()), id: \.offset) { idx, w in
            MetricGroup(title: "Workout \(idx + 1)" + (w.sport.map { " — \($0)" } ?? "")) {
                MetricRow(label: "Sport", value: w.sport ?? "--")
                MetricRow(label: "Start", value: w.startTime ?? "--")
                MetricRow(label: "End", value: w.endTime ?? "--")
                MetricRow(label: "Strain", value: w.strain.map { String(format: "%.1f", $0) } ?? "--")
                MetricRow(label: "Avg HR", value: w.averageHeartRate.map { "\(Int($0)) bpm" } ?? "--")
                MetricRow(label: "Max HR", value: w.maxHeartRate.map { "\(Int($0)) bpm" } ?? "--")
                MetricRow(label: "Energy", value: w.kilojoules.map { String(format: "%.0f kJ (%.0f kcal)", $0, $0 * 0.239) } ?? "--")
                MetricRow(label: "Distance", value: w.distanceMeters.map { String(format: "%.0f m", $0) } ?? "--")
                MetricRow(label: "Altitude Gain", value: w.altitudeGainMeters.map { String(format: "%.0f m", $0) } ?? "--")
                if let z = w.zones {
                    MetricRow(label: "Zone 1 (recovery)", value: z.zone1Minutes.map { "\(Int($0)) min" } ?? "--")
                    MetricRow(label: "Zone 2 (light)", value: z.zone2Minutes.map { "\(Int($0)) min" } ?? "--")
                    MetricRow(label: "Zone 3 (moderate)", value: z.zone3Minutes.map { "\(Int($0)) min" } ?? "--")
                    MetricRow(label: "Zone 4 (hard)", value: z.zone4Minutes.map { "\(Int($0)) min" } ?? "--")
                    MetricRow(label: "Zone 5 (max)", value: z.zone5Minutes.map { "\(Int($0)) min" } ?? "--")
                }
            }
        }
    }
}

struct AllWhoopMetricsView_Previews: PreviewProvider {
    static var previews: some View {
        AllWhoopMetricsView().preferredColorScheme(.dark)
    }
}
