//
//  WhoopModels.swift
//  Invisible_Health
//
//  Whoop-specific data models from Open Wearables
//

import Foundation

// MARK: - Whoop Recovery (OW /summaries/recovery item shape)
struct WhoopRecovery: Codable {
    let date: String?                      // "2026-05-30" — date-only string
    let recoveryScore: Double?             // 0-100%
    let restingHeartRateBpm: Double?
    let avgHrvSdnnMs: Double?
    let avgSpo2Percent: Double?
    let sleepDurationSeconds: Double?
    let sleepEfficiencyPercent: Double?

    // Backwards-compat aliases for code that was written against native Whoop names.
    var hrvMillis: Double? { avgHrvSdnnMs }
    var restingHeartRate: Double? { restingHeartRateBpm }
    var spO2Percentage: Double? { avgSpo2Percent }
    // OW doesn't expose these, but consumers expect them:
    var respiratoryRate: Double? { nil }
    var skinTempCelsius: Double? { nil }
    var hrvContribution: Double? { nil }
    var rhrContribution: Double? { nil }
    var sleepContribution: Double? { nil }

    var recoveryColor: String {
        guard let s = recoveryScore else { return "gray" }
        switch s {
        case 67...100: return "green"
        case 34...66: return "yellow"
        default: return "red"
        }
    }

    var recoveryLevel: String {
        guard let s = recoveryScore else { return "Unknown" }
        switch s {
        case 67...100: return "Ready to Perform"
        case 34...66: return "Moderate Recovery"
        default: return "Rest Recommended"
        }
    }
}

// MARK: - Whoop Strain (from OW /summaries/activity)
// Note: OW returns an empty array for users without recent activity, so most
// fields stay nil until there's data. Field names below are best-guess for
// when activity items do appear — adjust once we see a non-empty response.
struct WhoopStrain: Codable {
    let date: String?
    let dayStrain: Double?
    let averageHeartRate: Double?
    let maxHeartRate: Double?
    let kilojoules: Double?
    let workouts: [WhoopWorkout]?
    let cardiovascularLoad: Double?
    let muscularLoad: Double?

    var strainLevel: String {
        guard let s = dayStrain else { return "Unknown" }
        switch s {
        case 18...21: return "Overreaching"
        case 14...17.9: return "Strenuous"
        case 10...13.9: return "Moderate"
        default: return "Light"
        }
    }
}

// MARK: - Whoop Workout
struct WhoopWorkout: Codable {
    let id: String?
    let sport: String?
    let startTime: String?
    let endTime: String?
    let strain: Double?
    let averageHeartRate: Double?
    let maxHeartRate: Double?
    let kilojoules: Double?
    let distanceMeters: Double?
    let altitudeGainMeters: Double?
    let zones: HeartRateZones?
}

// MARK: - Heart Rate Zones
struct HeartRateZones: Codable {
    let zone1Minutes: Double?
    let zone2Minutes: Double?
    let zone3Minutes: Double?
    let zone4Minutes: Double?
    let zone5Minutes: Double?
}

// MARK: - Whoop Sleep (OW /summaries/sleep item shape)
struct WhoopSleep: Codable {
    let date: String?
    let startTime: String?
    let endTime: String?
    let durationMinutes: Double?
    let timeInBedMinutes: Double?
    let efficiencyPercent: Double?
    let stages: SleepStages?
    let interruptionsCount: Int?
    let napCount: Int?
    let napDurationMinutes: Double?
    let avgHeartRateBpm: Double?
    let avgHrvSdnnMs: Double?
    let avgRespiratoryRate: Double?
    let avgSpo2Percent: Double?

    // OW doesn't expose a single "sleep performance" number, so we use
    // efficiency_percent as the headline metric in the UI.
    var sleepPerformancePercentage: Double? { efficiencyPercent }
    var totalSleepMinutes: Double? { durationMinutes }
    var sleepEfficiency: Double? { efficiencyPercent }
    var awakeMinutes: Double? { stages?.awakeMinutes }
    var lightSleepMinutes: Double? { stages?.lightMinutes }
    var remSleepMinutes: Double? { stages?.remMinutes }
    var slowWaveSleepMinutes: Double? { stages?.deepMinutes }
    var respiratoryRate: Double? { avgRespiratoryRate }
    var disturbances: Int? { interruptionsCount }

    var sleepQuality: String {
        guard let p = sleepPerformancePercentage else { return "Unknown" }
        switch p {
        case 85...100: return "Excellent"
        case 70...84: return "Good"
        case 50...69: return "Fair"
        default: return "Poor"
        }
    }

    var timeInBedHours: Double {
        (timeInBedMinutes ?? ((totalSleepMinutes ?? 0) + (awakeMinutes ?? 0))) / 60.0
    }

    var timeAsleepHours: Double {
        (totalSleepMinutes ?? 0) / 60.0
    }
}

struct SleepStages: Codable {
    let awakeMinutes: Double?
    let lightMinutes: Double?
    let deepMinutes: Double?
    let remMinutes: Double?
}

// MARK: - Unified Health Metrics
// Not Codable: appleWorkouts holds HKWorkout (HealthKit) which isn't Codable,
// and this struct is only used as an in-memory aggregation, never serialized.
struct UnifiedHealthMetrics {
    let date: Date

    // From Apple Health (HealthKit)
    var appleHRV: Double?
    var appleRestingHR: Double?
    var appleSleepMinutes: Double?
    var appleSteps: Double?
    var appleVO2Max: Double?
    var appleActiveCalories: Double?
    var appleWorkouts: [HKWorkout]?

    // From Whoop (Open Wearables)
    var whoopRecovery: WhoopRecovery?
    var whoopStrain: WhoopStrain?
    var whoopSleep: WhoopSleep?

    // From CGM (via HealthKit)
    var glucoseMgDl: Double?
    var glucoseTrend: String? // rising, falling, stable
    var timeInRange: Double? // Percentage 70-180 mg/dL

    // Computed unified metrics
    var combinedRecoveryScore: Double {
        // Weighted average if both sources available
        if let appleHRV = appleHRV, let whoopScore = whoopRecovery?.recoveryScore {
            // Normalize Apple HRV to 0-100 scale (rough approximation)
            let normalizedAppleScore = min(100, (appleHRV / 60) * 100)
            return (normalizedAppleScore * 0.4 + whoopScore * 0.6)
        }
        return whoopRecovery?.recoveryScore ?? 0
    }

    var bestHRV: Double? {
        // Return higher value as it indicates better recovery
        if let apple = appleHRV, let whoop = whoopRecovery?.hrvMillis {
            return max(apple, whoop)
        }
        return appleHRV ?? whoopRecovery?.hrvMillis
    }

    var bestRestingHR: Double? {
        // Return lower value as it indicates better fitness
        if let apple = appleRestingHR, let whoop = whoopRecovery?.restingHeartRate {
            return min(apple, whoop)
        }
        return appleRestingHR ?? whoopRecovery?.restingHeartRate
    }

    var totalSleepHours: Double {
        let appleSleep = (appleSleepMinutes ?? 0) / 60
        let whoopSleep = (whoopSleep?.totalSleepMinutes ?? 0) / 60
        // Use Whoop if available as it's more accurate for sleep
        return whoopSleep > 0 ? whoopSleep : appleSleep
    }

    var trainingReadiness: TrainingReadiness {
        // Combine multiple signals for recommendation
        let recovery = combinedRecoveryScore
        let sleep = totalSleepHours
        let glucose = glucoseMgDl ?? 100 // Default to normal if no CGM

        if recovery > 67 && sleep > 7 && (70...140).contains(glucose) {
            return .high
        } else if recovery > 33 && sleep > 6 {
            return .moderate
        } else {
            return .low
        }
    }
}

enum TrainingReadiness {
    case high, moderate, low

    var recommendation: String {
        switch self {
        case .high:
            return "Ready for high-intensity training"
        case .moderate:
            return "Moderate effort recommended"
        case .low:
            return "Focus on recovery today"
        }
    }
}

// MARK: - Sync Status
struct SyncStatus: Codable {
    let provider: String
    let lastSync: Date?
    let nextSync: Date?
    let isActive: Bool
    let errorMessage: String?
}

// Extension to work with existing HKWorkout
import HealthKit
extension UnifiedHealthMetrics {
    mutating func mergeAppleHealthData(from healthManager: HealthManager) {
        // This will be called to merge Apple Health data
        self.appleSteps = healthManager.dailySteps
        // Additional merging logic will go here
    }
}