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
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                // 2. Inject it into the view hierarchy
                .environmentObject(notificationManager)
                // 3. Request permissions when app launches
                .onAppear {
                    notificationManager.requestAuthorization()
                }
        }
    }
}
