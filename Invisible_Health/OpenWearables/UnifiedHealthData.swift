//
//  UnifiedHealthData.swift
//  Invisible_Health
//
//  Merges Apple Health and Whoop data into unified metrics
//

import Foundation
import HealthKit
import SwiftUI

class UnifiedHealthData: ObservableObject {
    static let shared = UnifiedHealthData()

    // Managers
    private let healthManager = HealthManager.shared
    private let openWearables = OpenWearablesManager.shared

    // Published unified metrics
    @Published var todayMetrics: UnifiedHealthMetrics?
    @Published var isLoading = false
    @Published var lastUpdateTime: Date?

    // CGM specific
    @Published var currentGlucose: Double?
    @Published var glucoseTrend: GlucoseTrend = .stable
    @Published var timeInRange: Double = 0 // Percentage in 70-180 mg/dL

    private var updateTimer: Timer?

    init() {
        startPeriodicUpdates()
        setupObservers()
    }

    // MARK: - Public Methods
    func fetchUnifiedMetrics(completion: @escaping (UnifiedHealthMetrics?) -> Void) {
        var metrics = UnifiedHealthMetrics(date: Date())
        let group = DispatchGroup()

        isLoading = true

        // MARK: Apple Health Data
        group.enter()
        healthManager.fetchReadinessSnapshot { snapshot in
            metrics.appleHRV = snapshot.hrv
            metrics.appleRestingHR = snapshot.restingHR
            metrics.appleSleepMinutes = snapshot.timeAsleepHours * 60
            group.leave()
        }

        // Apple Steps
        group.enter()
        healthManager.fetchTodaySteps { steps in
            metrics.appleSteps = steps
            group.leave()
        }

        // Apple VO2Max
        group.enter()
        healthManager.fetchLatestSample(for: .vo2Max,
            unit: HKUnit.literUnit(with: .milli).unitDivided(by: HKUnit.gramUnit(with: .kilo)).unitDivided(by: HKUnit.minute())) { vo2 in
            metrics.appleVO2Max = vo2
            group.leave()
        }

        // Apple Workouts (Today)
        group.enter()
        healthManager.fetchRecentWorkouts(days: 1) { workouts in
            metrics.appleWorkouts = workouts
            metrics.appleActiveCalories = workouts.reduce(0) { $0 + ($1.totalEnergyBurned?.doubleValue(for: .kilocalorie()) ?? 0) }
            group.leave()
        }

        // MARK: CGM Data (via Apple Health)
        group.enter()
        fetchCGMData { glucose, trend, tir in
            metrics.glucoseMgDl = glucose
            metrics.glucoseTrend = trend
            metrics.timeInRange = tir
            group.leave()
        }

        // MARK: Whoop Data (if connected)
        if openWearables.isWhoopConnected {
            group.enter()
            openWearables.fetchWhoopRecovery { recovery in
                metrics.whoopRecovery = recovery
                group.leave()
            }

            group.enter()
            openWearables.fetchWhoopStrain { strain in
                metrics.whoopStrain = strain
                group.leave()
            }

            group.enter()
            openWearables.fetchWhoopSleep { sleep in
                metrics.whoopSleep = sleep
                group.leave()
            }
        }

        group.notify(queue: .main) {
            self.todayMetrics = metrics
            self.lastUpdateTime = Date()
            self.isLoading = false
            completion(metrics)
            print("✅ Unified metrics updated at \(Date())")
        }
    }

    // MARK: - CGM Data Fetching
    private func fetchCGMData(completion: @escaping (Double?, String?, Double?) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else {
            completion(nil, nil, nil)
            return
        }

        let glucoseType = HKQuantityType.quantityType(forIdentifier: .bloodGlucose)!
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        // Get latest glucose reading
        let latestQuery = HKSampleQuery(sampleType: glucoseType, predicate: predicate, limit: 1, sortDescriptors: [sortDescriptor]) { _, samples, _ in
            guard let sample = samples?.first as? HKQuantitySample else {
                completion(nil, nil, nil)
                return
            }

            let mgDl = sample.quantity.doubleValue(for: HKUnit(from: "mg/dL"))

            // Get trend from last 30 minutes
            let trendWindow = Date().addingTimeInterval(-30 * 60)
            let trendPredicate = HKQuery.predicateForSamples(withStart: trendWindow, end: now, options: .strictStartDate)

            let trendQuery = HKSampleQuery(sampleType: glucoseType, predicate: trendPredicate, limit: 10, sortDescriptors: [sortDescriptor]) { [weak self] _, trendSamples, _ in
                guard let trendSamples = trendSamples as? [HKQuantitySample], trendSamples.count > 1 else {
                    completion(mgDl, "stable", nil)
                    return
                }

                // Calculate trend
                let values = trendSamples.map { $0.quantity.doubleValue(for: HKUnit(from: "mg/dL")) }
                let trend = self?.calculateGlucoseTrend(values: values) ?? "stable"

                // Calculate time in range for today
                self?.calculateTimeInRange(from: startOfDay, to: now) { tir in
                    DispatchQueue.main.async {
                        self?.currentGlucose = mgDl
                        self?.glucoseTrend = GlucoseTrend(rawValue: trend) ?? .stable
                        self?.timeInRange = tir
                        completion(mgDl, trend, tir)
                    }
                }
            }
            self.healthManager.healthStore.execute(trendQuery)
        }
        healthManager.healthStore.execute(latestQuery)
    }

    private func calculateGlucoseTrend(values: [Double]) -> String {
        guard values.count >= 2 else { return "stable" }
        let recent = values.prefix(3).average() ?? values[0]
        let older = values.suffix(3).average() ?? values.last!
        let change = recent - older

        if change > 10 { return "rising" }
        if change < -10 { return "falling" }
        return "stable"
    }

    private func calculateTimeInRange(from start: Date, to end: Date, completion: @escaping (Double) -> Void) {
        let glucoseType = HKQuantityType.quantityType(forIdentifier: .bloodGlucose)!
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        let query = HKSampleQuery(sampleType: glucoseType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
            guard let samples = samples as? [HKQuantitySample], !samples.isEmpty else {
                completion(0)
                return
            }

            let inRangeCount = samples.filter { sample in
                let mgDl = sample.quantity.doubleValue(for: HKUnit(from: "mg/dL"))
                return (70...180).contains(mgDl)
            }.count

            let tir = (Double(inRangeCount) / Double(samples.count)) * 100
            completion(tir)
        }
        healthManager.healthStore.execute(query)
    }

    // MARK: - Recommendation Engine
    func getWorkoutRecommendation() -> WorkoutRecommendation {
        guard let metrics = todayMetrics else {
            return WorkoutRecommendation(type: .rest, intensity: .low, duration: 30, reason: "Insufficient data")
        }

        // Check recovery signals
        let recovery = metrics.combinedRecoveryScore
        let hrv = metrics.bestHRV ?? 0
        let sleep = metrics.totalSleepHours
        let glucose = metrics.glucoseMgDl ?? 100

        // Check for red flags
        if recovery < 33 {
            return WorkoutRecommendation(type: .recovery, intensity: .low, duration: 30, reason: "Low recovery score")
        }

        if sleep < 5 {
            return WorkoutRecommendation(type: .yoga, intensity: .low, duration: 20, reason: "Poor sleep quality")
        }

        if let glucose = metrics.glucoseMgDl {
            if glucose < 70 {
                return WorkoutRecommendation(type: .rest, intensity: .none, duration: 0, reason: "Low blood glucose")
            }
            if glucose > 250 {
                return WorkoutRecommendation(type: .walking, intensity: .low, duration: 20, reason: "Elevated blood glucose")
            }
        }

        // Training recommendations based on readiness
        switch metrics.trainingReadiness {
        case .high:
            // Check recent strain to avoid overtraining
            if let strain = metrics.whoopStrain?.dayStrain, strain > 15 {
                return WorkoutRecommendation(type: .recovery, intensity: .low, duration: 30, reason: "High recent strain")
            }
            return WorkoutRecommendation(type: .running, intensity: .high, duration: 45, reason: "Optimal recovery and readiness")

        case .moderate:
            return WorkoutRecommendation(type: .strength, intensity: .moderate, duration: 40, reason: "Moderate recovery status")

        case .low:
            return WorkoutRecommendation(type: .walking, intensity: .low, duration: 30, reason: "Focus on recovery")
        }
    }

    // MARK: - Setup
    private func setupObservers() {
        // Observe changes from both sources
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(healthDataUpdated),
            name: NSNotification.Name("HealthDataUpdated"),
            object: nil
        )
    }

    @objc private func healthDataUpdated() {
        fetchUnifiedMetrics { _ in }
    }

    private func startPeriodicUpdates() {
        updateTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.fetchUnifiedMetrics { _ in }
        }
        // Initial fetch
        fetchUnifiedMetrics { _ in }
    }
}

// MARK: - Supporting Types
enum GlucoseTrend: String {
    case rising = "rising"
    case falling = "falling"
    case stable = "stable"

    var icon: String {
        switch self {
        case .rising: return "arrow.up.right"
        case .falling: return "arrow.down.right"
        case .stable: return "arrow.right"
        }
    }

    var color: Color {
        switch self {
        case .rising: return .orange
        case .falling: return .blue
        case .stable: return .green
        }
    }
}

struct WorkoutRecommendation {
    enum WorkoutType {
        case running, cycling, strength, yoga, walking, recovery, rest
    }

    enum Intensity {
        case none, low, moderate, high
    }

    let type: WorkoutType
    let intensity: Intensity
    let duration: Int // minutes
    let reason: String

    var description: String {
        switch type {
        case .rest:
            return "Rest day recommended: \(reason)"
        case .recovery:
            return "\(duration) min recovery session: \(reason)"
        default:
            return "\(duration) min \(String(describing: type)) at \(String(describing: intensity)) intensity: \(reason)"
        }
    }
}

// MARK: - Dad's Wisdom Integration
extension UnifiedHealthData {
    func applyDadsWisdom(to metrics: UnifiedHealthMetrics) -> String {
        // This is where your dad's 40 years of experience gets encoded
        var wisdom = [String]()

        // Recovery-based wisdom
        if let recovery = metrics.whoopRecovery?.recoveryScore {
            switch recovery {
            case 0...33:
                wisdom.append("Listen to your body. Today is about restoration, not records.")
            case 34...66:
                wisdom.append("You can train, but keep it controlled. Save the heroics for green days.")
            case 67...100:
                wisdom.append("Your body is primed. This is when champions are made.")
            default:
                break
            }
        }

        // HRV wisdom
        if let hrv = metrics.bestHRV {
            if hrv < 30 {
                wisdom.append("Your nervous system needs care. Think recovery, not performance.")
            } else if hrv > 60 {
                wisdom.append("Strong HRV shows resilience. You've earned the right to push.")
            }
        }

        // Sleep wisdom
        if metrics.totalSleepHours < 6 {
            wisdom.append("Champions are made in bed too. Prioritize sleep tonight.")
        }

        // Glucose wisdom
        if let glucose = metrics.glucoseMgDl {
            if glucose < 80 && metrics.whoopStrain != nil {
                wisdom.append("Fuel up properly. Low glucose with high training is a recipe for burnout.")
            }
        }

        return wisdom.randomElement() ?? "Trust the process. Consistency beats intensity."
    }
}