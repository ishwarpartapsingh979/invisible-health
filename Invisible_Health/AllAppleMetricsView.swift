//
//  AllAppleMetricsView.swift
//  Invisible_Health
//
//  Raw dump of every Apple Health metric we currently fetch. No interpretation —
//  this is the "trust but verify" view. Grouped by Vitals / Sleep / Activity / CGM.
//

import SwiftUI
import HealthKit

struct AllAppleMetricsView: View {
    @StateObject private var healthManager = HealthManager.shared
    @StateObject private var unified = UnifiedHealthData.shared

    @State private var snapshot: HealthManager.ReadinessSnapshot?
    @State private var telemetryGap: HealthManager.TelemetryGapResult?
    @State private var todaySteps: Double = 0
    @State private var recentWorkouts: [HKWorkout] = []
    @State private var todayWaterMl: Double = 0
    @State private var isLoading = false
    @State private var lastUpdated: Date?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                vitalsSection
                sleepSection
                activitySection
                hydrationSection
                cgmSection

                Spacer(minLength: 40)
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
        }
        .background(Color.black.edgesIgnoringSafeArea(.all))
        .onAppear {
            if snapshot == nil { refresh() }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("APPLE HEALTH")
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

    // MARK: - Sections

    private var vitalsSection: some View {
        MetricGroup(title: "Vitals") {
            MetricRow(label: "HRV (SDNN)", value: format(snapshot?.hrv, suffix: " ms"))
            MetricRow(label: "Resting HR", value: format(snapshot?.restingHR, suffix: " bpm"))
            MetricRow(label: "VO₂ Max", value: format(snapshot?.vo2Max, suffix: " ml/kg/min"))
            MetricRow(label: "Body Mass", value: format(snapshot?.bodyMassKg, suffix: " kg"))
            MetricRow(label: "HR Recovery (1 min)", value: format(snapshot?.heartRateRecovery, suffix: " bpm"))
            MetricRow(label: "Walking Asymmetry", value: format(snapshot?.walkingAsymmetryPct, suffix: " %"))
            MetricRow(label: "Morning HR samples", value: "\(snapshot?.morningHRStream.count ?? 0)")
        }
    }

    private var sleepSection: some View {
        MetricGroup(title: "Sleep") {
            MetricRow(label: "Time in Bed (HK)", value: format(snapshot?.timeInBedHours, suffix: " h"))
            MetricRow(label: "Time Asleep (HK)", value: format(snapshot?.timeAsleepHours, suffix: " h"))
            MetricRow(label: "Proxy Sleep (telemetry gap)", value: format(telemetryGap.map { $0.proxyTimeInBed / 3600 }, suffix: " h"))
            MetricRow(label: "iPhone in-bed window", value: format(telemetryGap.map { $0.iPhoneInBedSeconds / 3600 }, suffix: " h"))
            MetricRow(label: "Watch put on", value: telemetryGap?.watchOnTime.map { dateString($0) } ?? "--")
        }
    }

    private var activitySection: some View {
        MetricGroup(title: "Activity (Today)") {
            MetricRow(label: "Steps", value: "\(Int(todaySteps))")
            MetricRow(label: "Workouts (last 2d)", value: "\(recentWorkouts.count)")
            ForEach(Array(recentWorkouts.prefix(5).enumerated()), id: \.offset) { _, w in
                let cals = Int(w.statistics(for: HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!)?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0)
                let name = HKWorkoutActivityType(rawValue: w.workoutActivityType.rawValue)?.name ?? "Workout"
                MetricRow(label: "↳ \(name)", value: "\(Int(w.duration / 60)) min · \(cals) kcal")
            }
        }
    }

    private var hydrationSection: some View {
        MetricGroup(title: "Hydration (Today)") {
            MetricRow(label: "Water", value: todayWaterMl > 0
                      ? String(format: "%.0f ml  (%.1f L)", todayWaterMl, todayWaterMl / 1000.0)
                      : "--")
            MetricRow(label: "vs 2 L target", value: todayWaterMl > 0
                      ? String(format: "%.0f%%", min(100, todayWaterMl / 2000.0 * 100))
                      : "--")
        }
    }

    private var cgmSection: some View {
        MetricGroup(title: "Glucose (CGM via HealthKit)") {
            MetricRow(label: "Current", value: unified.currentGlucose.map { "\(Int($0)) mg/dL" } ?? "--")
            MetricRow(label: "Trend", value: unified.glucoseTrend.rawValue.capitalized)
            MetricRow(label: "Time in Range (today)", value: unified.timeInRange > 0 ? String(format: "%.0f%%", unified.timeInRange) : "--")
        }
    }

    // MARK: - Refresh

    private func refresh() {
        isLoading = true
        let group = DispatchGroup()

        group.enter()
        healthManager.fetchReadinessSnapshot { s in
            DispatchQueue.main.async { self.snapshot = s }
            group.leave()
        }
        group.enter()
        healthManager.calculateTelemetryGapSleep { g in
            DispatchQueue.main.async { self.telemetryGap = g }
            group.leave()
        }
        group.enter()
        healthManager.fetchTodaySteps { s in
            DispatchQueue.main.async { self.todaySteps = s }
            group.leave()
        }
        group.enter()
        healthManager.fetchRecentWorkouts(days: 2) { w in
            DispatchQueue.main.async { self.recentWorkouts = w }
            group.leave()
        }
        group.enter()
        healthManager.fetchTodayWater { ml in
            DispatchQueue.main.async { self.todayWaterMl = ml }
            group.leave()
        }
        // CGM is fetched by UnifiedHealthData on its own timer, but kick it once
        unified.fetchUnifiedMetrics { _ in }

        group.notify(queue: .main) {
            self.isLoading = false
            self.lastUpdated = Date()
        }
    }

    private func format(_ value: Double?, suffix: String, digits: Int = 1) -> String {
        guard let v = value else { return "--" }
        return String(format: "%.\(digits)f%@", v, suffix)
    }

    private func dateString(_ d: Date) -> String {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .short
        return f.string(from: d)
    }
}

// MARK: - Shared building blocks used by Apple + Whoop dumps

struct MetricGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.gray)
                .padding(.bottom, 2)

            VStack(spacing: 0) {
                content
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 12)
            .background(Color.white.opacity(0.04))
            .cornerRadius(12)
        }
    }
}

struct MetricRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.callout)
                .foregroundColor(.white.opacity(0.85))
            Spacer()
            Text(value)
                .font(.system(.callout, design: .rounded))
                .foregroundColor(.white)
        }
        .padding(.vertical, 8)
        .overlay(
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 0.5),
            alignment: .bottom
        )
    }
}

struct AllAppleMetricsView_Previews: PreviewProvider {
    static var previews: some View {
        AllAppleMetricsView().preferredColorScheme(.dark)
    }
}
