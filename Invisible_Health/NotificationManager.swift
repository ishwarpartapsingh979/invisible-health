import Foundation
import UserNotifications
import ActivityKit
import SwiftUI
@MainActor
class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()
    
    // No longer showing a view, so this might not be needed for Flow 3.1,
    // but keeping it if we need to show alerts later.
    @Published var showYesterdaySummary: Bool = false
    
    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }
    
    // Flag to prevent infinite loops of notifications during testing
    static var hasScheduled = false
    
    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                print("Notification permission granted")
                self.configureCategories() // Register Actions
                // Only schedule ONCE per session
                if !Self.hasScheduled {
                    self.scheduleDailyWakeUp()
                    Self.hasScheduled = true
                }
            } else if let error = error {
                print("Notification permission error: \(error.localizedDescription)")
            }
        }
    }
    
    func configureCategories() {
        // Define Actions for Smart Log
        // ✅ WhatsApp Style: Inline Text Input
        let editAction = UNTextInputNotificationAction(
            identifier: "EDIT_ACTION",
            title: "Edit",
            options: [],
            textInputButtonTitle: "Save",
            textInputPlaceholder: "e.g. 2 eggs, not 3"
        )
        
        let dismissAction = UNNotificationAction(identifier: "DISMISS_ACTION", title: "Dismiss", options: [.destructive])
        
        let smartCategory = UNNotificationCategory(identifier: "SMART_LOG_CATEGORY", actions: [editAction, dismissAction], intentIdentifiers: [], options: [])
        
        // ✅ Water Log Category (Undo)
        let undoAction = UNNotificationAction(identifier: "UNDO_ACTION", title: "Undo", options: [.destructive, .authenticationRequired])
        let waterCategory = UNNotificationCategory(identifier: "WATER_LOG_CATEGORY", actions: [undoAction], intentIdentifiers: [], options: [])
        
        // Existing Wake Up Category
        let initializeAction = UNNotificationAction(identifier: "INITIALIZE_ACTION", title: "Initialize", options: [])
        let snoozeAction = UNNotificationAction(identifier: "SNOOZE_ACTION", title: "Snooze", options: [])
        let wakeUpCategory = UNNotificationCategory(identifier: "WAKE_UP_CATEGORY", actions: [snoozeAction, initializeAction], intentIdentifiers: [], options: [])
        
        // MARK: - Diet Check-In Category (10 PM)
        let nailedItAction    = UNNotificationAction(identifier: "DIET_NAILED_IT",   title: "🟢 Nailed it",   options: [])
        let minorBadAction    = UNNotificationAction(identifier: "DIET_MINOR_BAD",   title: "🟡 Minor bad",   options: [])
        let minorGoodAction   = UNNotificationAction(identifier: "DIET_MINOR_GOOD",  title: "🟡 Minor good",  options: [])
        let fullyBadAction    = UNNotificationAction(identifier: "DIET_FULLY_BAD",   title: "🔴 Fully bad",   options: [])
        let dietCategory = UNNotificationCategory(
            identifier: "DIET_CHECKIN_CATEGORY",
            actions: [nailedItAction, minorBadAction, minorGoodAction, fullyBadAction],
            intentIdentifiers: [],
            options: []
        )

        UNUserNotificationCenter.current().setNotificationCategories([smartCategory, waterCategory, wakeUpCategory, dietCategory])
    }
    
    func scheduleDailyWakeUp() {
        // Clear old requests
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["daily_wake_up", "morning_check", "lunch_check", "dinner_check"])

        // MARK: - Meal check-in notifications commented out
        // let times = [
        //     ("Good Morning! ☀️", "Time for breakfast log? 🍳", 9, "morning_check"),
        //     ("Lunch Check-In 🥗", "What's on the menu today?", 13, "lunch_check"),
        //     ("Dinner Time 🌙", "Don't forget to log your dinner.", 20, "dinner_check")
        // ]
        //
        // for (title, body, hour, id) in times {
        //     let content = UNMutableNotificationContent()
        //     content.title = title
        //     content.body = body
        //     content.sound = .default
        //     content.categoryIdentifier = "WAKE_UP_CATEGORY"
        //
        //     var dateComponents = DateComponents()
        //     dateComponents.hour = hour
        //     dateComponents.minute = 0
        //
        //     let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        //     let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        //
        //     UNUserNotificationCenter.current().add(request)
        // }
        //
        // print("⏰ Scheduled 3 Daily Check-ins (9 AM, 1 PM, 8 PM)")

        scheduleWaterReminders()
        scheduleDietCheckIn()
    }

    // MARK: - Water Reminders (4L/day goal)
    // 4L = ~13-14 glasses of 300ml. Reminders every 45 min from 7am to 10pm = 20 slots.
    func scheduleWaterReminders() {
        // Remove any existing water reminders
        let existingIds = (0..<20).map { "water_reminder_\($0)" }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: existingIds)

        let waterMessages = [
            "Time to hydrate! 💧 Drink a glass of water.",
            "Water check! 💧 Stay on track for your 4L goal.",
            "Hydration reminder 💧 — grab some water now.",
            "Keep it up! 💧 Another glass towards 4 litres.",
            "Don't forget to drink water! 💧",
            "Halfway there? 💧 Keep sipping to hit 4L today."
        ]

        // Every 45 minutes from 7:00 AM to 10:00 PM
        let startHour = 7
        let startMinute = 0
        let intervalMinutes = 45
        let totalMinutesAvailable = (22 - 7) * 60 // 7am to 10pm = 900 min
        let slots = totalMinutesAvailable / intervalMinutes // ~20 slots

        for i in 0..<slots {
            let totalMinutes = startHour * 60 + startMinute + i * intervalMinutes
            let hour = totalMinutes / 60
            let minute = totalMinutes % 60
            guard hour < 22 else { break }

            let content = UNMutableNotificationContent()
            content.title = "Drink Water 💧"
            content.body = waterMessages[i % waterMessages.count]
            content.sound = .default

            var dateComponents = DateComponents()
            dateComponents.hour = hour
            dateComponents.minute = minute

            let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
            let request = UNNotificationRequest(identifier: "water_reminder_\(i)", content: content, trigger: trigger)
            UNUserNotificationCenter.current().add(request)
        }

        print("💧 Scheduled water reminders every 45 min from 7 AM to 10 PM")
    }

    // MARK: - Diet Check-In (10 PM daily)
    func scheduleDietCheckIn() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["diet_checkin_10pm"])

        let content = UNMutableNotificationContent()
        content.title = "How was your diet today? 🍽️"
        content.body = "Tap to rate your eating for the day."
        content.sound = .default
        content.categoryIdentifier = "DIET_CHECKIN_CATEGORY"

        var dateComponents = DateComponents()
        dateComponents.hour = 22
        dateComponents.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(identifier: "diet_checkin_10pm", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)

        print("🍽️ Scheduled daily diet check-in at 10 PM")
    }

    // MARK: - UNUserNotificationCenterDelegate
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        if response.actionIdentifier == "INITIALIZE_ACTION" {
            // ✅ Flow 3.1: User tapped "Initialize" button
            print("🚀 User tapped Initialize. Triggering Agent...")

            // Trigger the Agent Manager
            // Note: We are passing nil for location for now (Agent assumes "Home/Unknown").
            // In a real app, we would fetch location here.
            // Wake up Agent on Step Change
            AgentManager.shared.wakeUpAgent(userId: "00000000-0000-0000-0000-000000000001", fcmToken: nil)

            // Live Activity commented out
            // startLiveActivity()
        } else if response.actionIdentifier == "EDIT_ACTION" {
            // ✅ WhatsApp Style: Handle Text Input
            if let textResponse = response as? UNTextInputNotificationResponse {
                let userText = textResponse.userText
                print("📝 User Edited Log Inline: \(userText)")
            }
        } else if response.actionIdentifier == "UNDO_ACTION" {
            // ✅ Water Undo Action
            print("🔄 Undo Water Logged. Decrementing count...")
            // Logic to decrement water count in Live Activity
            for activity in Activity<NutritionActivityAttributes>.activities {
                var updatedState = activity.content.state
                updatedState.waterIntake = max(0, updatedState.waterIntake - 1)
                await activity.update(ActivityContent(state: updatedState, staleDate: nil))
            }
            
            // 📡 Backend Sync: Undo the log (Fire and Forget)
            let userId = "test_user_1"
            if let url = URL(string: "https://us-central1-gen-lang-client-0009721575.cloudfunctions.net/run-agent?action=undo_water&user_id=\(userId)") {
                let task = URLSession.shared.dataTask(with: url)
                task.resume()
                print("🚀 Backend Water Undo Triggered")
            }
        } else if ["DIET_NAILED_IT", "DIET_MINOR_BAD", "DIET_MINOR_GOOD", "DIET_FULLY_BAD"].contains(response.actionIdentifier) {
            // Save diet rating to UserDefaults keyed by today's date
            let ratingMap = [
                "DIET_NAILED_IT":  "nailed_it",
                "DIET_MINOR_BAD":  "minor_bad",
                "DIET_MINOR_GOOD": "minor_good",
                "DIET_FULLY_BAD":  "fully_bad"
            ]
            if let rating = ratingMap[response.actionIdentifier] {
                let dateKey = "diet_rating_\(Self.todayDateString())"
                UserDefaults.standard.set(rating, forKey: dateKey)
                print("✅ Diet rating saved: \(rating) for \(dateKey)")
            }
        } else if response.actionIdentifier == UNNotificationDefaultActionIdentifier {
            // ✅ Flow 3.1 Alternative: User tapped the Notification Body (Opens App)
            print("User tapped Notification Body. Starting Live Activity...")
            // Check category to decide action
            if response.notification.request.content.categoryIdentifier == "WAKE_UP_CATEGORY" {
                // Live Activity commented out
                // startLiveActivity()
            }
        }
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        return [.banner, .sound, .list]
    }
    
    // MARK: - Live Activity
    
    func startLiveActivity() {
        // Ensure Activities are enabled
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("Live Activities are not enabled!")
            return
        }
        
        // Initial State for Flow 3.1
        let attributes = NutritionActivityAttributes(dailyCalorieGoal: 2500)
        let contentState = NutritionActivityAttributes.ContentState(
            caloriesRemaining: 2500,
            proteinGrams: 0,
            stepCount: 0,
            lastUpdated: Date()
        )
        
        do {
            let activity = try Activity<NutritionActivityAttributes>.request(
                attributes: attributes,
                content: .init(state: contentState, staleDate: nil),
                pushType: nil // Changed to nil to bypass Push Capability for local testing
            )
            print("✅ Live Activity Started Successfully! ID: \(activity.id)")
        } catch {
            print("❌ Error starting Live Activity: \(error.localizedDescription)")
        }
    }
    // MARK: - Helpers

    nonisolated static func todayDateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    /// Returns the diet rating for a given date string (e.g. "2026-02-15"), or nil if not yet rated.
    nonisolated static func dietRating(for dateString: String) -> String? {
        return UserDefaults.standard.string(forKey: "diet_rating_\(dateString)")
    }

    func simulateBackendAnalysis() {
        print("Simulating Backend Analysis...")
        // ... (simulation code)
    }
    
    // ✅ Phase 2.1: Instant Notification Helper
    func shortNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = "SMART_LOG_CATEGORY"
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error scheduling notification: \(error.localizedDescription)")
            }
        }
    }
}
