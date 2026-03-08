//
//  HealthManager.swift
//  Invisible_Health
//
//  Created by Ishwar Partap Singh on 23/12/25.
//

import Foundation
import HealthKit

class HealthManager: ObservableObject {
    static let shared = HealthManager()
    
    let healthStore = HKHealthStore()
    
    @Published var dailySteps: Double = 0
    @Published var isAuthorized = false
    
    // MARK: - 1. Authorization
    func requestAuthorization() {
        // READ Types (Sensors)
        // READ Types (Sensors)
        let readTypes: Set<HKObjectType> = [
            HKObjectType.quantityType(forIdentifier: HKQuantityTypeIdentifier.stepCount)!,
            HKObjectType.quantityType(forIdentifier: HKQuantityTypeIdentifier.activeEnergyBurned)!,
            HKObjectType.workoutType(),
            
            // Phase 3.1: Elite Metrics
            // Biomechanics
            HKObjectType.quantityType(forIdentifier: HKQuantityTypeIdentifier.runningVerticalOscillation)!,
            HKObjectType.quantityType(forIdentifier: HKQuantityTypeIdentifier.runningGroundContactTime)!,
            HKObjectType.quantityType(forIdentifier: HKQuantityTypeIdentifier.runningPower)!,
            HKObjectType.quantityType(forIdentifier: HKQuantityTypeIdentifier.runningSpeed)!,
            
            // Cardio
            HKObjectType.quantityType(forIdentifier: HKQuantityTypeIdentifier.heartRate)!,
            HKObjectType.quantityType(forIdentifier: HKQuantityTypeIdentifier.vo2Max)!,
            HKObjectType.quantityType(forIdentifier: HKQuantityTypeIdentifier.heartRateRecoveryOneMinute)!,
            
            // CNS / Recovery
            HKObjectType.quantityType(forIdentifier: HKQuantityTypeIdentifier.heartRateVariabilitySDNN)!,
            HKObjectType.quantityType(forIdentifier: HKQuantityTypeIdentifier.restingHeartRate)!,

            // New Tab: Readiness Engine
            HKObjectType.categoryType(forIdentifier: HKCategoryTypeIdentifier.sleepAnalysis)!,
            HKObjectType.quantityType(forIdentifier: HKQuantityTypeIdentifier.bodyMass)!,
            HKObjectType.quantityType(forIdentifier: HKQuantityTypeIdentifier.walkingAsymmetryPercentage)!
        ]
        
        // WRITE Types (Nutrition)
        let writeTypes: Set<HKSampleType> = [
            HKObjectType.quantityType(forIdentifier: .dietaryEnergyConsumed)!,
            HKObjectType.quantityType(forIdentifier: .dietaryProtein)!,
            HKObjectType.quantityType(forIdentifier: .dietaryCarbohydrates)!,
            HKObjectType.quantityType(forIdentifier: .dietaryFatTotal)!,
            HKObjectType.quantityType(forIdentifier: .dietaryWater)!
        ]
        
        healthStore.requestAuthorization(toShare: writeTypes, read: readTypes) { success, error in
            if success {
                print("✅ HealthKit Authorized (Elite Mode)")
                DispatchQueue.main.async {
                    self.isAuthorized = true
                    self.fetchTodaySteps()
                    self.enableBackgroundDelivery()       // Steps observer (existing)
                    self.registerMorningAuditObserver()   // HR observer (new tab only)
                }
            } else {
                print("❌ HealthKit Auth Error: \(String(describing: error))")
            }
        }
    }
    
    // MARK: - 2. Read Loop (Body Awareness)
    func fetchTodaySteps(completion: ((Double) -> Void)? = nil) {
        let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
        
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate)
        
        let query = HKStatisticsQuery(quantityType: stepType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, error in
            guard let result = result, let sum = result.sumQuantity() else {
                completion?(0)
                return
            }
            
            let steps = sum.doubleValue(for: HKUnit.count())
            DispatchQueue.main.async {
                self.dailySteps = steps
                print("🦶 Today's Steps: \(Int(steps))")
                completion?(steps)
            }
        }
        
        healthStore.execute(query)
    }
    
    // MARK: - 2a. Elite Fetchers (Phase 3.1)
    
    // FETCH WORKOUTS (Last N Days - using device timezone)
    func fetchRecentWorkouts(days: Int = 3, completion: @escaping ([HKWorkout]) -> Void) {
        let now = Date()
        var calendar = Calendar.current
        // Set timezone to IST (Indian Standard Time)
        calendar.timeZone = TimeZone(identifier: "Asia/Kolkata")!

        // Feb 15, 2026 IST 00:00:00 as hardcoded start date
        let dateComponents = DateComponents(year: 2026, month: 2, day: 15, hour: 0, minute: 0, second: 0)
        let startDate = calendar.date(from: dateComponents)!

        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: now, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        let query = HKSampleQuery(sampleType: .workoutType(), predicate: predicate, limit: 100, sortDescriptors: [sortDescriptor]) { _, samples, error in
            guard let workouts = samples as? [HKWorkout], error == nil else {
                print("❌ Error fetching workouts: \(String(describing: error))")
                completion([])
                return
            }

            print("🏋️ Found \(workouts.count) workouts (Last \(days) Days).")
            DispatchQueue.main.async {
                completion(workouts)
            }
        }
        healthStore.execute(query)
    }
    
    // GENERIC LATEST SAMPLE FETCHER (HRV, RHR, VO2)
    func fetchLatestSample(for identifier: HKQuantityTypeIdentifier, unit: HKUnit, completion: @escaping (Double?) -> Void) {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { completion(nil); return }
        
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        let query = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: [sortDescriptor]) { _, samples, _ in
            guard let sample = samples?.first as? HKQuantitySample else {
                completion(nil)
                return
            }
            
            let value = sample.quantity.doubleValue(for: unit)
            DispatchQueue.main.async {
                completion(value)
            }
        }
        healthStore.execute(query)
    }
    
    // HELPER: Fetch Biometrics for Summary
    func fetchEliteBiometrics(completion: @escaping (Double?, Double?, Double?) -> Void) {
        // Returns (VO2Max, HRV, RHR)
        var vo2: Double?
        var hrv: Double?
        var rhr: Double?

        let group = DispatchGroup()

        // VO2 Max (ml/kg/min)
        group.enter()
        let vo2Unit = HKUnit.literUnit(with: .milli).unitDivided(by: HKUnit.gramUnit(with: .kilo)).unitDivided(by: HKUnit.minute())
        fetchLatestSample(for: .vo2Max, unit: vo2Unit) { value in
            vo2 = value
            group.leave()
        }

        // HRV (ms)
        group.enter()
        fetchLatestSample(for: .heartRateVariabilitySDNN, unit: .secondUnit(with: .milli)) { value in
            hrv = value
            group.leave()
        }

        // Resting HR (bpm)
        group.enter()
        fetchLatestSample(for: .restingHeartRate, unit: HKUnit.count().unitDivided(by: .minute())) { value in
            rhr = value
            group.leave()
        }

        group.notify(queue: .main) {
            print("🫀 Elite Biometrics - VO2: \(String(describing: vo2)), HRV: \(String(describing: hrv)), RHR: \(String(describing: rhr))")
            completion(vo2, hrv, rhr)
        }
    }

    // MARK: - Historical Recovery Data (30 Days)

    struct DailyRecoveryMetric {
        let date: Date
        let hrv: Double?
        let restingHR: Double?
        let sleepHours: Double?
    }

    func fetch30DayRecoveryMetrics(completion: @escaping ([DailyRecoveryMetric]) -> Void) {
        let calendar = Calendar.current
        let now = Date()
        guard let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: now) else {
            completion([])
            return
        }

        var dailyMetrics: [Date: DailyRecoveryMetric] = [:]
        let group = DispatchGroup()

        // Fetch HRV samples
        group.enter()
        fetchHistoricalSamples(
            for: .heartRateVariabilitySDNN,
            unit: .secondUnit(with: .milli),
            startDate: thirtyDaysAgo,
            endDate: now
        ) { samples in
            for sample in samples {
                let dayStart = calendar.startOfDay(for: sample.date)
                if dailyMetrics[dayStart] == nil {
                    dailyMetrics[dayStart] = DailyRecoveryMetric(date: dayStart, hrv: nil, restingHR: nil, sleepHours: nil)
                }
                // Update with average if multiple samples per day
                let current = dailyMetrics[dayStart]!
                dailyMetrics[dayStart] = DailyRecoveryMetric(
                    date: dayStart,
                    hrv: sample.value,
                    restingHR: current.restingHR,
                    sleepHours: current.sleepHours
                )
            }
            group.leave()
        }

        // Fetch Resting HR samples
        group.enter()
        fetchHistoricalSamples(
            for: .restingHeartRate,
            unit: HKUnit.count().unitDivided(by: .minute()),
            startDate: thirtyDaysAgo,
            endDate: now
        ) { samples in
            for sample in samples {
                let dayStart = calendar.startOfDay(for: sample.date)
                if dailyMetrics[dayStart] == nil {
                    dailyMetrics[dayStart] = DailyRecoveryMetric(date: dayStart, hrv: nil, restingHR: nil, sleepHours: nil)
                }
                let current = dailyMetrics[dayStart]!
                dailyMetrics[dayStart] = DailyRecoveryMetric(
                    date: dayStart,
                    hrv: current.hrv,
                    restingHR: sample.value,
                    sleepHours: current.sleepHours
                )
            }
            group.leave()
        }

        // Fetch Sleep data
        group.enter()
        fetchHistoricalSleep(startDate: thirtyDaysAgo, endDate: now) { sleepData in
            for (date, hours) in sleepData {
                let dayStart = calendar.startOfDay(for: date)
                if dailyMetrics[dayStart] == nil {
                    dailyMetrics[dayStart] = DailyRecoveryMetric(date: dayStart, hrv: nil, restingHR: nil, sleepHours: nil)
                }
                let current = dailyMetrics[dayStart]!
                dailyMetrics[dayStart] = DailyRecoveryMetric(
                    date: dayStart,
                    hrv: current.hrv,
                    restingHR: current.restingHR,
                    sleepHours: hours
                )
            }
            group.leave()
        }

        group.notify(queue: .main) {
            let sortedMetrics = dailyMetrics.values.sorted { $0.date < $1.date }
            completion(sortedMetrics)
        }
    }

    struct HealthSample {
        let date: Date
        let value: Double
    }

    func fetchHistoricalSamples(
        for identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        startDate: Date,
        endDate: Date,
        completion: @escaping ([HealthSample]) -> Void
    ) {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: identifier) else {
            completion([])
            return
        }

        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        let query = HKSampleQuery(
            sampleType: quantityType,
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: [sortDescriptor]
        ) { _, samples, error in
            guard let samples = samples as? [HKQuantitySample], error == nil else {
                completion([])
                return
            }

            let healthSamples = samples.map { sample in
                HealthSample(date: sample.startDate, value: sample.quantity.doubleValue(for: unit))
            }
            completion(healthSamples)
        }

        healthStore.execute(query)
    }

    func fetchHistoricalSleep(
        startDate: Date,
        endDate: Date,
        completion: @escaping ([Date: Double]) -> Void
    ) {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            completion([:])
            return
        }

        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        let query = HKSampleQuery(
            sampleType: sleepType,
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: [sortDescriptor]
        ) { _, samples, error in
            guard let samples = samples as? [HKCategorySample], error == nil else {
                completion([:])
                return
            }

            var sleepByDay: [Date: TimeInterval] = [:]
            let calendar = Calendar.current

            for sample in samples {
                // Only count asleep (not in bed)
                if sample.value == HKCategoryValueSleepAnalysis.asleep.rawValue ||
                   sample.value == HKCategoryValueSleepAnalysis.asleepCore.rawValue ||
                   sample.value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue ||
                   sample.value == HKCategoryValueSleepAnalysis.asleepREM.rawValue {
                    let duration = sample.endDate.timeIntervalSince(sample.startDate)
                    let dayStart = calendar.startOfDay(for: sample.startDate)
                    sleepByDay[dayStart, default: 0] += duration
                }
            }

            // Convert to hours
            let sleepHoursByDay = sleepByDay.mapValues { $0 / 3600.0 }
            completion(sleepHoursByDay)
        }

        healthStore.execute(query)
    }
    
    // Returns (Avg Oscillation, Avg GCT, Avg Power, Avg HR, Max HR)
    func fetchWorkoutMetrics(workout: HKWorkout, completion: @escaping (Double?, Double?, Double?, Double?, Double?) -> Void) {
        // ... (Existing implementation kept as is for compatibility)
        let predicate = HKQuery.predicateForSamples(withStart: workout.startDate, end: workout.endDate, options: .strictStartDate)
        var avgOscillation: Double?; var avgGCT: Double?; var avgPower: Double?; var avgHR: Double?; var maxHR: Double?
        let group = DispatchGroup()
        
        group.enter()
        let oscType = HKQuantityType.quantityType(forIdentifier: .runningVerticalOscillation)!
        let oscQuery = HKStatisticsQuery(quantityType: oscType, quantitySamplePredicate: predicate, options: .discreteAverage) { _, result, _ in
            avgOscillation = result?.averageQuantity()?.doubleValue(for: .meterUnit(with: .centi))
            group.leave()
        }
        healthStore.execute(oscQuery)
        
        group.enter()
        let gctType = HKQuantityType.quantityType(forIdentifier: .runningGroundContactTime)!
        let gctQuery = HKStatisticsQuery(quantityType: gctType, quantitySamplePredicate: predicate, options: .discreteAverage) { _, result, _ in
            avgGCT = result?.averageQuantity()?.doubleValue(for: .secondUnit(with: .milli))
            group.leave()
        }
        healthStore.execute(gctQuery)
        
        group.enter()
        let pwrType = HKQuantityType.quantityType(forIdentifier: .runningPower)!
        let pwrQuery = HKStatisticsQuery(quantityType: pwrType, quantitySamplePredicate: predicate, options: .discreteAverage) { _, result, _ in
            avgPower = result?.averageQuantity()?.doubleValue(for: .watt())
            group.leave()
        }
        healthStore.execute(pwrQuery)
        
        group.enter()
        let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
        let hrQuery = HKStatisticsQuery(quantityType: hrType, quantitySamplePredicate: predicate, options: [.discreteAverage, .discreteMax]) { _, result, _ in
            avgHR = result?.averageQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
            maxHR = result?.maximumQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
            group.leave()
        }
        healthStore.execute(hrQuery)
        
        group.notify(queue: .main) {
            completion(avgOscillation, avgGCT, avgPower, avgHR, maxHR)
        }
    }
    
    private func getWorkoutName(type: HKWorkoutActivityType) -> String {
        switch type {
        case .running: return "Running"
        case .cycling: return "Cycling"
        case .walking: return "Walking"
        case .swimming: return "Swimming"
        case .traditionalStrengthTraining: return "Strength Training"
        case .functionalStrengthTraining: return "Functional Strength"
        case .highIntensityIntervalTraining: return "HIIT"
        case .yoga: return "Yoga"
        case .hiking: return "Hiking"
        case .crossTraining: return "Cross Training"
        case .elliptical: return "Elliptical"
        case .rowing: return "Rowing"
        case .stairClimbing: return "Stair Climbing"
        case .soccer: return "Soccer"
        case .americanFootball: return "American Football"
        case .tennis: return "Tennis"
        default: return "Workout"
        }
    }

    // MARK: - Olympic Level Data Fetcher (New)
    func fetchComprehensiveWorkoutData(workout: HKWorkout, completion: @escaping ([String: Any]) -> Void) {
        var metrics: [String: Any] = [:]
        
        // 0. Metadata & Type
        metrics["workout_name"] = getWorkoutName(type: workout.workoutActivityType)
        if let isIndoor = workout.metadata?[HKMetadataKeyIndoorWorkout] as? Bool {
            metrics["is_indoor"] = isIndoor
        } else {
            // Fallback: Infer from type if needed, or assume outdoor for GPS sports
            metrics["is_indoor"] = false
        }
        
        let group = DispatchGroup()
        let predicate = HKQuery.predicateForSamples(withStart: workout.startDate, end: workout.endDate, options: .strictStartDate)
        
        // 1. Basic Metrics (Reuse existing logic or duplicate for independence)
        // Heart Rate
        group.enter()
        let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
        let hrQuery = HKStatisticsQuery(quantityType: hrType, quantitySamplePredicate: predicate, options: [.discreteAverage, .discreteMax, .discreteMin]) { _, result, _ in
            if let avg = result?.averageQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute())) { metrics["avg_hr"] = avg }
            if let max = result?.maximumQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute())) { metrics["max_hr"] = max }
            if let min = result?.minimumQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute())) { metrics["min_hr"] = min }
            group.leave()
        }
        healthStore.execute(hrQuery)
        
        // Active Calories
        group.enter()
        if let calType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) {
             let calQuery = HKStatisticsQuery(quantityType: calType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, _ in
                 if let cals = result?.sumQuantity()?.doubleValue(for: .kilocalorie()) { metrics["active_calories"] = cals }
                 group.leave()
             }
             healthStore.execute(calQuery)
        } else { group.leave() }
        
        // 2. Sport-Specific Metrics
        switch workout.workoutActivityType {
        case .running:
            // Cadence (Steps per Minute)
            group.enter()
            let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
            let stepQuery = HKStatisticsQuery(quantityType: stepType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, _ in
                if let steps = result?.sumQuantity()?.doubleValue(for: .count()) {
                    let durationMin = workout.duration / 60
                    if durationMin > 0 { metrics["avg_cadence"] = steps / durationMin }
                }
                group.leave()
            }
            healthStore.execute(stepQuery)
            
            // Stride Length
            group.enter()
            if let strideType = HKQuantityType.quantityType(forIdentifier: .runningStrideLength) {
                let strideQuery = HKStatisticsQuery(quantityType: strideType, quantitySamplePredicate: predicate, options: .discreteAverage) { _, result, _ in
                    if let stride = result?.averageQuantity()?.doubleValue(for: .meter()) { metrics["avg_stride_len"] = stride }
                    group.leave()
                }
                healthStore.execute(strideQuery)
            } else { group.leave() }
            
            // Vertical Oscillation
            group.enter()
            let oscType = HKQuantityType.quantityType(forIdentifier: .runningVerticalOscillation)!
            let oscQuery = HKStatisticsQuery(quantityType: oscType, quantitySamplePredicate: predicate, options: .discreteAverage) { _, result, _ in
                if let osc = result?.averageQuantity()?.doubleValue(for: .meterUnit(with: .centi)) { metrics["avg_oscillation_cm"] = osc }
                group.leave()
            }
            healthStore.execute(oscQuery)
            
            // GCT
            group.enter()
            let gctType = HKQuantityType.quantityType(forIdentifier: .runningGroundContactTime)!
            let gctQuery = HKStatisticsQuery(quantityType: gctType, quantitySamplePredicate: predicate, options: .discreteAverage) { _, result, _ in
                if let gct = result?.averageQuantity()?.doubleValue(for: .secondUnit(with: .milli)) { metrics["avg_gct_ms"] = gct }
                group.leave()
            }
            healthStore.execute(gctQuery)
            
            // Power (Running)
            group.enter()
            let pwrType = HKQuantityType.quantityType(forIdentifier: .runningPower)!
            let pwrQuery = HKStatisticsQuery(quantityType: pwrType, quantitySamplePredicate: predicate, options: .discreteAverage) { _, result, _ in
                if let pwr = result?.averageQuantity()?.doubleValue(for: .watt()) { metrics["avg_power_watts"] = pwr }
                group.leave()
            }
            healthStore.execute(pwrQuery)
            
        case .cycling:
            // Distance Cycling
            group.enter()
            let distType = HKQuantityType.quantityType(forIdentifier: .distanceCycling)!
            let distQuery = HKStatisticsQuery(quantityType: distType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, _ in
                if let dist = result?.sumQuantity()?.doubleValue(for: .meter()) { metrics["distance_meters"] = dist }
                group.leave()
            }
            healthStore.execute(distQuery)
            
            // Power (Cycling - if available)
            group.enter()
            if let pwrType = HKQuantityType.quantityType(forIdentifier: .cyclingPower) {
                let pwrQuery = HKStatisticsQuery(quantityType: pwrType, quantitySamplePredicate: predicate, options: .discreteAverage) { _, result, _ in
                    if let pwr = result?.averageQuantity()?.doubleValue(for: .watt()) { metrics["avg_power_watts"] = pwr }
                    group.leave()
                }
                healthStore.execute(pwrQuery)
            } else { group.leave() }
            
            // Cadence (Cycling - RPM)
            group.enter()
            if let cadType = HKQuantityType.quantityType(forIdentifier: .cyclingCadence) {
                let cadQuery = HKStatisticsQuery(quantityType: cadType, quantitySamplePredicate: predicate, options: .discreteAverage) { _, result, _ in
                    if let cad = result?.averageQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute())) { metrics["avg_cadence"] = cad }
                    group.leave()
                }
                healthStore.execute(cadQuery)
            } else { group.leave() }

        case .swimming:
            // Distance Swimming
            group.enter()
            let distType = HKQuantityType.quantityType(forIdentifier: .distanceSwimming)!
            let distQuery = HKStatisticsQuery(quantityType: distType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, _ in
                if let dist = result?.sumQuantity()?.doubleValue(for: .meter()) { metrics["distance_meters"] = dist }
                group.leave()
            }
            healthStore.execute(distQuery)
            
            // Stroke Count
            group.enter()
            let strokeType = HKQuantityType.quantityType(forIdentifier: .swimmingStrokeCount)!
            let strokeQuery = HKStatisticsQuery(quantityType: strokeType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, _ in
                if let strokes = result?.sumQuantity()?.doubleValue(for: .count()) { metrics["total_strokes"] = strokes }
                group.leave()
            }
            healthStore.execute(strokeQuery)
            
        case .soccer, .americanFootball, .rugby:
            // Team Sports: Distance Calculation (Walking/Running)
            group.enter()
            let distType = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)!
            let distQuery = HKStatisticsQuery(quantityType: distType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, _ in
                if let dist = result?.sumQuantity()?.doubleValue(for: .meter()) { metrics["distance_meters"] = dist }
                group.leave()
            }
            healthStore.execute(distQuery)
            
        case .downhillSkiing, .snowboarding:
            // Snow Sports: Distance Downhill
            group.enter()
            let distType = HKQuantityType.quantityType(forIdentifier: .distanceDownhillSnowSports)!
            let distQuery = HKStatisticsQuery(quantityType: distType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, _ in
                if let dist = result?.sumQuantity()?.doubleValue(for: .meter()) { metrics["distance_meters"] = dist }
                group.leave()
            }
            healthStore.execute(distQuery)
            
        default:
            // Generic: Try to get distance if it exists (Walking/Running default)
            group.enter()
            let distType = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)!
            let distQuery = HKStatisticsQuery(quantityType: distType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, _ in
                if let dist = result?.sumQuantity()?.doubleValue(for: .meter()) { metrics["distance_meters"] = dist }
                group.leave()
            }
            healthStore.execute(distQuery)
        }

        group.notify(queue: .main) {
            completion(metrics)
        }
    }

    
    // MARK: - 3. Write Loop (Nutrition Sync)
    func logDietaryData(calories: Double, protein: Double? = nil, carbs: Double? = nil, fat: Double? = nil, date: Date = Date()) {
        guard isAuthorized else { return }
        
        var samples: [HKSample] = []
        
        // Calories
        if calories > 0 {
            let type = HKQuantityType.quantityType(forIdentifier: .dietaryEnergyConsumed)!
            let quantity = HKQuantity(unit: .kilocalorie(), doubleValue: calories)
            let sample = HKQuantitySample(type: type, quantity: quantity, start: date, end: date)
            samples.append(sample)
        }
        
        // Macros (Placeholder logic: Apple Health requires grams)
        if let p = protein, p > 0 {
             let type = HKQuantityType.quantityType(forIdentifier: .dietaryProtein)!
             let qty = HKQuantity(unit: .gram(), doubleValue: p)
             samples.append(HKQuantitySample(type: type, quantity: qty, start: date, end: date))
        }
        if let c = carbs, c > 0 {
             let type = HKQuantityType.quantityType(forIdentifier: .dietaryCarbohydrates)!
             let qty = HKQuantity(unit: .gram(), doubleValue: c)
             samples.append(HKQuantitySample(type: type, quantity: qty, start: date, end: date))
        }
        if let f = fat, f > 0 {
             let type = HKQuantityType.quantityType(forIdentifier: .dietaryFatTotal)!
             let qty = HKQuantity(unit: .gram(), doubleValue: f)
             samples.append(HKQuantitySample(type: type, quantity: qty, start: date, end: date))
        }
        
        if !samples.isEmpty {
            healthStore.save(samples) { success, error in
                if success {
                    print("✅ Saved to HealthKit: \(calories) kcal + Macros")
                } else {
                    print("❌ Error saving to HealthKit: \(String(describing: error))")
                }
            }
        }
    }
    
    // MARK: - NEW TAB: Readiness Engine Fetchers
    // All functions below are exclusively for the new Readiness/Recommendation tab.
    // None of these are called by any existing WorkoutView, WorkoutDetailView, or CoachChatView code.

    /// Fetches last night's sleep: returns (timeInBedHours, timeAsleepHours).
    /// Uses iPhone's passive sleep tracking (HKCategoryValueSleepAnalysis).
    func fetchSleepData(completion: @escaping (Double, Double) -> Void) {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            completion(0, 0); return
        }

        let now = Date()
        // Window: yesterday noon to now — captures last night's sleep
        let windowStart = Calendar.current.date(byAdding: .hour, value: -18, to: now)!
        let predicate = HKQuery.predicateForSamples(withStart: windowStart, end: now, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: 100, sortDescriptors: [sortDescriptor]) { _, samples, error in
            guard let samples = samples as? [HKCategorySample], error == nil else {
                completion(0, 0); return
            }

            var inBedSeconds: Double = 0
            var asleepSeconds: Double = 0

            for sample in samples {
                let duration = sample.endDate.timeIntervalSince(sample.startDate)
                switch sample.value {
                case HKCategoryValueSleepAnalysis.inBed.rawValue:
                    inBedSeconds += duration
                case HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                     HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                     HKCategoryValueSleepAnalysis.asleepREM.rawValue,
                     HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue:
                    asleepSeconds += duration
                default:
                    break
                }
            }

            let inBedHours = inBedSeconds / 3600
            let asleepHours = asleepSeconds / 3600
            print("😴 Sleep — In Bed: \(String(format: "%.1f", inBedHours))h, Asleep: \(String(format: "%.1f", asleepHours))h")
            DispatchQueue.main.async { completion(inBedHours, asleepHours) }
        }
        healthStore.execute(query)
    }

    /// Fetches latest body mass in kg.
    func fetchBodyMass(completion: @escaping (Double?) -> Void) {
        fetchLatestSample(for: .bodyMass, unit: .gramUnit(with: .kilo), completion: completion)
    }

    /// Fetches latest walking asymmetry percentage (0–100).
    /// High values (>5%) indicate tight hamstrings/glutes or gait imbalance.
    func fetchWalkingAsymmetry(completion: @escaping (Double?) -> Void) {
        fetchLatestSample(for: .walkingAsymmetryPercentage, unit: .percent(), completion: completion)
    }

    /// Fetches heart rate samples from the first 15 minutes after waking (6–9 AM window today).
    /// Used to calculate the orthostatic spike: difference between lying HR and standing HR.
    /// Returns array of (timestamp, bpm) tuples sorted ascending.
    func fetchMorningHRStream(completion: @escaping ([(Date, Double)]) -> Void) {
        guard let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            completion([]); return
        }

        let calendar = Calendar.current
        let now = Date()
        // 6 AM to 9 AM today
        guard let windowStart = calendar.date(bySettingHour: 6, minute: 0, second: 0, of: now),
              let windowEnd   = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: now) else {
            completion([]); return
        }

        let predicate = HKQuery.predicateForSamples(withStart: windowStart, end: windowEnd, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        let query = HKSampleQuery(sampleType: hrType, predicate: predicate, limit: 50, sortDescriptors: [sortDescriptor]) { _, samples, error in
            guard let samples = samples as? [HKQuantitySample], error == nil else {
                completion([]); return
            }

            let bpmUnit = HKUnit.count().unitDivided(by: .minute())
            let stream: [(Date, Double)] = samples.map { ($0.startDate, $0.quantity.doubleValue(for: bpmUnit)) }
            print("🌅 Morning HR stream: \(stream.count) samples (6–9 AM)")
            DispatchQueue.main.async { completion(stream) }
        }
        healthStore.execute(query)
    }

    /// Composite readiness snapshot for the new tab.
    /// Fetches HRV, RHR, VO2, sleep, body mass, walking asymmetry, and morning HR stream in parallel.
    /// Returns a typed struct so the new tab has a single clean data object.
    struct ReadinessSnapshot {
        var hrv: Double?                         // ms — primary CNS metric
        var restingHR: Double?                   // bpm
        var vo2Max: Double?                      // ml/kg/min
        var bodyMassKg: Double?                  // kg
        var timeInBedHours: Double               // hours
        var timeAsleepHours: Double              // hours
        var walkingAsymmetryPct: Double?         // % — injury prevention veto
        var morningHRStream: [(Date, Double)]    // orthostatic spike raw data
        var heartRateRecovery: Double?           // bpm dropped in 1 min post-workout
    }

    func fetchReadinessSnapshot(completion: @escaping (ReadinessSnapshot) -> Void) {
        var snapshot = ReadinessSnapshot(
            hrv: nil, restingHR: nil, vo2Max: nil, bodyMassKg: nil,
            timeInBedHours: 0, timeAsleepHours: 0,
            walkingAsymmetryPct: nil, morningHRStream: [],
            heartRateRecovery: nil
        )

        let group = DispatchGroup()

        group.enter()
        fetchLatestSample(for: .heartRateVariabilitySDNN, unit: .secondUnit(with: .milli)) { val in
            snapshot.hrv = val; group.leave()
        }

        group.enter()
        fetchLatestSample(for: .restingHeartRate, unit: HKUnit.count().unitDivided(by: .minute())) { val in
            snapshot.restingHR = val; group.leave()
        }

        group.enter()
        let vo2Unit = HKUnit.literUnit(with: .milli).unitDivided(by: HKUnit.gramUnit(with: .kilo)).unitDivided(by: HKUnit.minute())
        fetchLatestSample(for: .vo2Max, unit: vo2Unit) { val in
            snapshot.vo2Max = val; group.leave()
        }

        group.enter()
        fetchBodyMass { val in
            snapshot.bodyMassKg = val; group.leave()
        }

        group.enter()
        fetchSleepData { inBed, asleep in
            snapshot.timeInBedHours = inBed
            snapshot.timeAsleepHours = asleep
            group.leave()
        }

        group.enter()
        fetchWalkingAsymmetry { val in
            snapshot.walkingAsymmetryPct = val; group.leave()
        }

        group.enter()
        fetchMorningHRStream { stream in
            snapshot.morningHRStream = stream; group.leave()
        }

        group.enter()
        fetchLatestSample(for: .heartRateRecoveryOneMinute, unit: HKUnit.count().unitDivided(by: .minute())) { val in
            snapshot.heartRateRecovery = val; group.leave()
        }

        group.notify(queue: .main) {
            print("✅ ReadinessSnapshot ready — HRV: \(String(describing: snapshot.hrv)), RHR: \(String(describing: snapshot.restingHR)), Sleep: \(String(format: "%.1f", snapshot.timeAsleepHours))h")
            completion(snapshot)
        }
    }

    // MARK: - NEW TAB: Morning Audit Engine
    // Three precision functions + one orchestrator. Zero overlap with workout tab.

    // -------------------------------------------------------------------------
    // 1. TELEMETRY GAP SLEEP CALCULATOR
    //    Detects when the watch was removed (last HR of the evening) and
    //    when it was put back on (first HR of the morning), then returns the
    //    gap as proxyTimeInBed.  Falls back to iPhone's passive .inBed if
    //    the gap logic fails (e.g. watch worn all night).
    // -------------------------------------------------------------------------
    struct TelemetryGapResult {
        var watchOffTime: Date?          // last HR reading before the gap
        var watchOnTime: Date?           // first HR reading after the gap
        var proxyTimeInBed: TimeInterval // seconds between the two (primary)
        var iPhoneInBedSeconds: Double   // iPhone passive fallback (secondary)
    }

    func calculateTelemetryGapSleep(completion: @escaping (TelemetryGapResult) -> Void) {
        guard let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            completion(TelemetryGapResult(watchOffTime: nil, watchOnTime: nil,
                                          proxyTimeInBed: 0, iPhoneInBedSeconds: 0))
            return
        }

        let now = Date()
        let windowStart = Calendar.current.date(byAdding: .hour, value: -24, to: now)!
        let predicate = HKQuery.predicateForSamples(withStart: windowStart, end: now, options: .strictStartDate)
        // Ascending so we can walk the timeline forward
        let sortAsc = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        let hrQuery = HKSampleQuery(sampleType: hrType, predicate: predicate,
                                    limit: HKObjectQueryNoLimit, sortDescriptors: [sortAsc]) { [weak self] _, samples, error in
            guard let self = self,
                  let hrSamples = samples as? [HKQuantitySample], !hrSamples.isEmpty, error == nil else {
                completion(TelemetryGapResult(watchOffTime: nil, watchOnTime: nil,
                                              proxyTimeInBed: 0, iPhoneInBedSeconds: 0))
                return
            }

            // Find the largest gap between consecutive HR readings — that's the watch-off window.
            // We require the gap to be at least 1 hour to avoid confusing workout rest periods.
            let minimumGapSeconds: TimeInterval = 3600 // 1 hour

            var largestGap: TimeInterval = 0
            var gapStart: Date? = nil
            var gapEnd: Date? = nil

            for i in 1..<hrSamples.count {
                let gap = hrSamples[i].startDate.timeIntervalSince(hrSamples[i - 1].endDate)
                if gap > largestGap && gap >= minimumGapSeconds {
                    largestGap = gap
                    gapStart = hrSamples[i - 1].endDate   // watch came off
                    gapEnd   = hrSamples[i].startDate      // watch went back on
                }
            }

            print("🕐 Telemetry Gap — Watch off: \(String(describing: gapStart)), Watch on: \(String(describing: gapEnd)), Gap: \(String(format: "%.1f", largestGap / 3600))h")

            // Fallback: iPhone passive .inBed via sleepAnalysis
            self.fetchSleepData { _, _ in
                // We only need the raw inBed seconds for validation; fetchSleepData already logs it.
                // Re-query here narrowed to .inBed only for the secondary figure.
            }

            // Get iPhone .inBed seconds independently for the result struct
            guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
                DispatchQueue.main.async {
                    completion(TelemetryGapResult(
                        watchOffTime: gapStart,
                        watchOnTime: gapEnd,
                        proxyTimeInBed: largestGap,
                        iPhoneInBedSeconds: 0
                    ))
                }
                return
            }

            let sleepStart = Calendar.current.date(byAdding: .hour, value: -18, to: now)!
            let sleepPredicate = HKQuery.predicateForSamples(withStart: sleepStart, end: now, options: .strictStartDate)
            let sleepQuery = HKSampleQuery(sampleType: sleepType, predicate: sleepPredicate,
                                           limit: 100, sortDescriptors: nil) { _, sleepSamples, _ in
                var inBedSeconds: Double = 0
                if let categorySamples = sleepSamples as? [HKCategorySample] {
                    for s in categorySamples where s.value == HKCategoryValueSleepAnalysis.inBed.rawValue {
                        inBedSeconds += s.endDate.timeIntervalSince(s.startDate)
                    }
                }

                DispatchQueue.main.async {
                    completion(TelemetryGapResult(
                        watchOffTime: gapStart,
                        watchOnTime: gapEnd,
                        proxyTimeInBed: largestGap,
                        iPhoneInBedSeconds: inBedSeconds
                    ))
                }
            }
            self.healthStore.execute(sleepQuery)
        }
        healthStore.execute(hrQuery)
    }

    // -------------------------------------------------------------------------
    // 2. ORTHOSTATIC SPIKE CALCULATOR
    //    Once the first morning HR timestamp is known (from above), queries
    //    all HR samples in the 15 minutes that follow and returns averageBPM
    //    and peakBPM.  A high peak (>20 bpm above RHR) signals CNS reactivity.
    // -------------------------------------------------------------------------
    struct OrthostasisResult {
        var windowStart: Date
        var windowEnd: Date
        var averageBPM: Double   // mean HR in the 15-min window
        var peakBPM: Double      // max HR in the 15-min window
        var sampleCount: Int
    }

    func calculateOrthostaticSpike(from firstMorningHRTime: Date,
                                   completion: @escaping (OrthostasisResult?) -> Void) {
        guard let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            completion(nil); return
        }

        let windowEnd = firstMorningHRTime.addingTimeInterval(15 * 60) // +15 minutes
        let predicate = HKQuery.predicateForSamples(withStart: firstMorningHRTime,
                                                     end: windowEnd,
                                                     options: .strictStartDate)

        // Use a statistics query for avg + max in one round-trip
        let statsQuery = HKStatisticsQuery(
            quantityType: hrType,
            quantitySamplePredicate: predicate,
            options: [.discreteAverage, .discreteMax]
        ) { _, result, error in
            guard error == nil, let result = result else {
                completion(nil); return
            }

            let bpmUnit = HKUnit.count().unitDivided(by: .minute())
            let avg  = result.averageQuantity()?.doubleValue(for: bpmUnit) ?? 0
            let peak = result.maximumQuantity()?.doubleValue(for: bpmUnit) ?? 0

            // Also get sample count for confidence scoring
            let countQuery = HKSampleQuery(
                sampleType: hrType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, _ in
                let count = samples?.count ?? 0
                let orthoResult = OrthostasisResult(
                    windowStart: firstMorningHRTime,
                    windowEnd: windowEnd,
                    averageBPM: avg,
                    peakBPM: peak,
                    sampleCount: count
                )
                print("🌡️ Orthostatic Spike — Avg: \(String(format: "%.0f", avg)) bpm, Peak: \(String(format: "%.0f", peak)) bpm, Samples: \(count)")
                DispatchQueue.main.async { completion(orthoResult) }
            }
            self.healthStore.execute(countQuery)
        }
        healthStore.execute(statsQuery)
    }

    // -------------------------------------------------------------------------
    // 3. DAILY HRV & RHR BASELINE FETCHER
    //    Queries today's calendar day specifically (not just "most recent ever")
    //    so the AI always works with same-day baselines.
    // -------------------------------------------------------------------------
    struct DailyBaselineResult {
        var hrv: Double?         // ms SDNN — primary CNS signal
        var restingHR: Double?   // bpm — secondary load signal
        var hrvTimestamp: Date?
        var rhrTimestamp: Date?
    }

    func fetchDailyBaseline(completion: @escaping (DailyBaselineResult) -> Void) {
        var result = DailyBaselineResult()
        let group = DispatchGroup()

        let todayStart = Calendar.current.startOfDay(for: Date())
        let todayPredicate = HKQuery.predicateForSamples(withStart: todayStart, end: Date(), options: .strictStartDate)
        let sortDesc = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        // HRV — today first, fall back to latest ever if today has none yet
        group.enter()
        if let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) {
            let hrvQuery = HKSampleQuery(sampleType: hrvType, predicate: todayPredicate,
                                         limit: 1, sortDescriptors: [sortDesc]) { [weak self] _, samples, _ in
                guard let self = self else { group.leave(); return }
                if let sample = samples?.first as? HKQuantitySample {
                    result.hrv = sample.quantity.doubleValue(for: .secondUnit(with: .milli))
                    result.hrvTimestamp = sample.startDate
                    group.leave()
                } else {
                    // fallback: last available reading
                    self.fetchLatestSample(for: .heartRateVariabilitySDNN, unit: .secondUnit(with: .milli)) { val in
                        result.hrv = val
                        group.leave()
                    }
                }
            }
            healthStore.execute(hrvQuery)
        } else { group.leave() }

        // RHR — today first, fall back to latest ever
        group.enter()
        if let rhrType = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) {
            let rhrUnit = HKUnit.count().unitDivided(by: .minute())
            let rhrQuery = HKSampleQuery(sampleType: rhrType, predicate: todayPredicate,
                                          limit: 1, sortDescriptors: [sortDesc]) { [weak self] _, samples, _ in
                guard let self = self else { group.leave(); return }
                if let sample = samples?.first as? HKQuantitySample {
                    result.restingHR = sample.quantity.doubleValue(for: rhrUnit)
                    result.rhrTimestamp = sample.startDate
                    group.leave()
                } else {
                    self.fetchLatestSample(for: .restingHeartRate, unit: rhrUnit) { val in
                        result.restingHR = val
                        group.leave()
                    }
                }
            }
            healthStore.execute(rhrQuery)
        } else { group.leave() }

        group.notify(queue: .main) {
            print("📊 Daily Baseline — HRV: \(String(describing: result.hrv))ms, RHR: \(String(describing: result.restingHR))bpm")
            completion(result)
        }
    }

    // -------------------------------------------------------------------------
    // 4. MORNING AUDIT ORCHESTRATOR
    //    Single entry point called by the HKObserverQuery on first morning HR.
    //    Runs all three calculations in the correct dependency order:
    //    Step A → telemetry gap (finds watchOnTime)
    //    Step B → orthostatic spike (needs watchOnTime from Step A)
    //    Step C → daily baseline (independent, runs in parallel with B)
    //    Background-safe: registered via a separate HKObserverQuery on heartRate
    //    so it triggers even when the app is not open.
    // -------------------------------------------------------------------------
    struct MorningAuditResult {
        var telemetryGap: TelemetryGapResult
        var orthostaticSpike: OrthostasisResult?
        var dailyBaseline: DailyBaselineResult
    }

    /// Registers the background HKObserverQuery for heartRate.
    /// Called once from requestAuthorization (after isAuthorized = true).
    /// Completely separate from the steps observer in enableBackgroundDelivery().
    func registerMorningAuditObserver() {
        guard let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return }

        // Enable background delivery for heart rate (immediate frequency —
        // HealthKit will batch but we want the wake-up as soon as possible)
        healthStore.enableBackgroundDelivery(for: hrType, frequency: .immediate) { success, error in
            if success {
                print("⚡️ Background Delivery enabled for HeartRate (Morning Audit)")
            } else {
                print("❌ HeartRate background delivery failed: \(String(describing: error))")
            }
        }

        let observer = HKObserverQuery(sampleType: hrType, predicate: nil) { [weak self] _, completionHandler, error in
            guard let self = self, error == nil else {
                completionHandler()
                return
            }
            // Only run the audit during the morning window (5 AM – 10 AM device time)
            // to avoid triggering on every workout HR update during the day.
            let calendar = Calendar.current
            let hour = calendar.component(.hour, from: Date())
            guard hour >= 5 && hour < 10 else {
                completionHandler()
                return
            }

            print("🌅 Morning HR observer fired — running audit...")
            self.performMorningAudit { result in
                print("✅ Morning Audit complete — proxy sleep: \(String(format: "%.1f", result.telemetryGap.proxyTimeInBed / 3600))h, ortho peak: \(String(describing: result.orthostaticSpike?.peakBPM)) bpm, HRV: \(String(describing: result.dailyBaseline.hrv))ms")
                // Store result for the new tab to read when user opens app
                self.cachedMorningAudit = result

                // Immediately compute the full recommendation using fresh audit data
                // so it's ready before the user even opens the app.
                print("⚡️ Auto-computing morning recommendation from audit...")
                AgentManager.shared.fetchWorkoutRecommendation { recommendation in
                    guard let rec = recommendation else {
                        print("❌ Morning auto-recommendation failed")
                        return
                    }
                    // Cache it so RecommendationView shows it instantly on open
                    AgentManager.shared.cachedMorningRecommendation = rec

                    // Fire a local notification so the user knows it's ready
                    let body = "\(rec.recommended_workout_type) · \(rec.recommended_duration_min) min · \(rec.recommended_intensity). Tap to send to Watch."
                    NotificationManager.shared.shortNotification(
                        title: "Today's workout is ready 💪",
                        body: body
                    )
                    print("🔔 Morning recommendation notification fired: \(rec.headline)")
                }
            }
            completionHandler()
        }
        healthStore.execute(observer)
    }

    /// Cached result so the new tab UI can read it synchronously on open.
    @Published var cachedMorningAudit: MorningAuditResult? = nil

    func performMorningAudit(completion: @escaping (MorningAuditResult) -> Void) {
        // Step A: Telemetry gap → gives us watchOnTime for the spike window
        calculateTelemetryGapSleep { [weak self] gapResult in
            guard let self = self else { return }

            let group = DispatchGroup()
            var spikeResult: OrthostasisResult? = nil
            var baselineResult = DailyBaselineResult()

            // Step B: Orthostatic spike — depends on watchOnTime from Step A
            if let watchOnTime = gapResult.watchOnTime {
                group.enter()
                self.calculateOrthostaticSpike(from: watchOnTime) { spike in
                    spikeResult = spike
                    group.leave()
                }
            }

            // Step C: Daily HRV + RHR baseline — independent, runs in parallel
            group.enter()
            self.fetchDailyBaseline { baseline in
                baselineResult = baseline
                group.leave()
            }

            group.notify(queue: .main) {
                let auditResult = MorningAuditResult(
                    telemetryGap: gapResult,
                    orthostaticSpike: spikeResult,
                    dailyBaseline: baselineResult
                )
                completion(auditResult)
            }
        }
    }

    // MARK: - 4. Background Delivery (Wake on Move)
    func enableBackgroundDelivery() {
        guard isAuthorized else { return }
        
        let type = HKObjectType.quantityType(forIdentifier: .stepCount)!
        
        // 1. Tell HealthKit to wake us up
        healthStore.enableBackgroundDelivery(for: type, frequency: .hourly) { success, error in
            if success {
                print("⚡️ Background Delivery Enabled for Steps")
            } else {
                print("❌ Failed to enable background delivery: \(String(describing: error))")
            }
        }
        
        // 2. Set up the Observer Query
        let query = HKObserverQuery(sampleType: type, predicate: nil) { query, completionHandler, error in
            if let error = error {
                print("❌ Observer Error: \(error)")
                completionHandler()
                return
            }
            
            print("⚡️ Background Update Received: Steps Changed!")
            
            // 3. Wake the Agent
            self.fetchTodaySteps { steps in
                // Only wake if significant steps change? 
                // Currently just wake up. Steps are passed in wakeUpAgent.
                AgentManager.shared.wakeUpAgent(userId: "test_user_1")
                completionHandler()
            }
        }
        
        healthStore.execute(query)
    }
}
