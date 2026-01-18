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
        
        UNUserNotificationCenter.current().setNotificationCategories([smartCategory, waterCategory, wakeUpCategory])
    }
    
    func scheduleDailyWakeUp() {
        let content = UNMutableNotificationContent()
        content.title = "Good Morning! ☀️"
        content.body = "Your Agent is ready. Initialize?"
        content.sound = .default
        content.categoryIdentifier = "WAKE_UP_CATEGORY"
        
        // REAL TRIGGER: 8:00 AM Daily
        var dateComponents = DateComponents()
        dateComponents.hour = 8
        dateComponents.minute = 0
        let dailyTrigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let dailyRequest = UNNotificationRequest(identifier: "daily_wake_up", content: content, trigger: dailyTrigger)
        
        // TEST TRIGGER: 10 Seconds from now (For you to test immediately)
        let testTrigger = UNTimeIntervalNotificationTrigger(timeInterval: 10, repeats: false)
        let testRequest = UNNotificationRequest(identifier: "test_wake_up", content: content, trigger: testTrigger)
        
        UNUserNotificationCenter.current().add(dailyRequest)
        UNUserNotificationCenter.current().add(testRequest)
        print("⏰ Scheduled Morning Warning (8 AM) + Test Warning (10s)")
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
            
            // Also start the Live Activity to show the status
            startLiveActivity()
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
        } else if response.actionIdentifier == UNNotificationDefaultActionIdentifier {
            // ✅ Flow 3.1 Alternative: User tapped the Notification Body (Opens App)
            print("User tapped Notification Body. Starting Live Activity...")
            // Check category to decide action
            if response.notification.request.content.categoryIdentifier == "WAKE_UP_CATEGORY" {
                startLiveActivity()
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
    func simulateBackendAnalysis() {
        print("Simulating Backend Analysis...")
        
        // Schedule notification after 2 seconds to simulate AI processing time
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            let content = UNMutableNotificationContent()
            content.title = "✅ Saved to directly log"
            content.body = "Salmon & Rice Bowl • 650 kcal • 45g Protein"
            content.sound = .default
            content.categoryIdentifier = "SMART_LOG_CATEGORY" // We will use this later for actions
            
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
            
            UNUserNotificationCenter.current().add(request) { error in
                if let error = error {
                    print("Error scheduling smart notification: \(error.localizedDescription)")
                } else {
                    print("Smart notification scheduled!")
                }
            }
        }
    }
}
