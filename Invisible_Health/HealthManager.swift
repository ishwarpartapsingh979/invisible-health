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
        let readTypes: Set<HKObjectType> = [
            HKObjectType.quantityType(forIdentifier: .stepCount)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.workoutType()
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
                print("✅ HealthKit Authorized")
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
                print("Steps: 0 (or error)")
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
