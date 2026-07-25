//
//  Invisible_HealthApp.swift
//  Invisible_Health
//
//  Created by Ishwar Partap Singh on 18/12/25.
//

import SwiftUI
@main
struct Invisible_HealthApp: App {
    // 1. Initialize our Manager
    @StateObject private var notificationManager = NotificationManager.shared
    // Multi-user: the signed-in per-user identity. Gates the app until there's a
    // user_id (signed in with Apple, or a dev override set in VoiceConfig).
    @StateObject private var auth = AuthManager.shared

    var body: some Scene {
        WindowGroup {
            Group {
                if auth.isSignedIn {
                    ContentView()
                        // 2. Inject it into the view hierarchy
                        .environmentObject(notificationManager)
                        // 3. Request permissions when app launches
                        .onAppear {
                            // Request HealthKit Permissions (Phase F)
                            HealthManager.shared.requestAuthorization()

                            notificationManager.requestAuthorization()
                            // Dogfood v2: Summary retired — no launch-time agent wake-up.
                            // AgentManager.shared.wakeUpAgent()
                        }
                } else {
                    SignInView()
                }
            }
            .onAppear { auth.refreshCredentialState() }
        }
    }
}
