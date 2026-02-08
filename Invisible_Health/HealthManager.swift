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
            HKObjectType.quantityType(forIdentifier: HKQuantityTypeIdentifier.restingHeartRate)!
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
                    self.enableBackgroundDelivery() // Start Watching ⚡️
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
    
    // FETCH WORKOUTS (Last 3 Days)
    func fetchRecentWorkouts(days: Int = 3, completion: @escaping ([HKWorkout]) -> Void) {
        let now = Date()
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: now)
        // Go back (days - 1) days to include today + 2 previous days
        let startDate = calendar.date(byAdding: .day, value: -(days - 1), to: startOfToday)!
        
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
