//
//  LogWaterIntent.swift
//  Invisible_Health
//
//  Created by Ishwar Partap Singh on 23/12/25.
//

import AppIntents
import ActivityKit
import Foundation
import UserNotifications
public struct LogWaterIntent: LiveActivityIntent {
    public static var title: LocalizedStringResource = "Log Water"
    
    public init() {}
    
    public func perform() async throws -> some IntentResult {
        print("💧 Log Water Intent Triggered")
        
        // 1. Update Live Activity
        for activity in Activity<NutritionActivityAttributes>.activities {
            var updatedState = activity.content.state
            updatedState.waterIntake += 1 // Increment by 1L (or 1 unit)
            updatedState.lastUpdated = Date()
            
            await activity.update(
                ActivityContent(state: updatedState, staleDate: nil)
            )
            print("💧 Live Activity Updated: \(updatedState.waterIntake)L")
        }
        
        // 2. Schedule Notification with Undo Action
        scheduleWaterNotification()
        
        // 3. Persist to Backend (Fire and Forget)
        let userId = "test_user_1" // TODO: Use real ID
        if let url = URL(string: "https://us-central1-gen-lang-client-0009721575.cloudfunctions.net/run-agent?action=log_water&user_id=\(userId)") {
            let task = URLSession.shared.dataTask(with: url)
            task.resume()
            print("🚀 Backend Water Log Triggered")
        }
        
        return .result()
    }
    
    func scheduleWaterNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Water Logged 💧"
        content.body = "Added 1L to your daily intake."
        content.sound = .default
        content.categoryIdentifier = "WATER_LOG_CATEGORY"
        
        // Trigger immediately (0.1s)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error scheduling water notification: \(error.localizedDescription)")
            }
        }
    }
}
