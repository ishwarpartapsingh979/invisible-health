//
//  NutritionActivityAttributes.swift
//  Invisible_Health
//
//  Created by Ishwar Partap Singh on 18/12/25.
//

import ActivityKit
import Foundation
public struct NutritionActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic state that changes over time
        public var caloriesRemaining: Int
        public var proteinGrams: Int
        public var stepCount: Int
        public var waterIntake: Int // New field for Phase 3
        public var lastUpdated: Date
        
        public init(caloriesRemaining: Int, proteinGrams: Int, stepCount: Int, waterIntake: Int = 0, lastUpdated: Date = Date()) {
            self.caloriesRemaining = caloriesRemaining
            self.proteinGrams = proteinGrams
            self.stepCount = stepCount
            self.waterIntake = waterIntake
            self.lastUpdated = lastUpdated
        }
    }
    // Fixed attributes that don't change during the activity
    public var dailyCalorieGoal: Int
    
    public init(dailyCalorieGoal: Int) {
        self.dailyCalorieGoal = dailyCalorieGoal
    }
}
