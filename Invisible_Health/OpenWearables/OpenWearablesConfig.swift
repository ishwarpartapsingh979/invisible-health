//
//  OpenWearablesConfig.swift
//  Invisible_Health
//
//  Configuration for the self-hosted Open Wearables backend
//  (https://github.com/the-momentum/open-wearables)
//

import Foundation

struct OpenWearablesConfig {
    // MARK: - API Configuration
    #if DEBUG
    static let baseURL = "http://localhost:8000/api/v1"
    #else
    static let baseURL = "https://your-production-url.com/api/v1"
    #endif

    // MARK: - Endpoint builders
    struct Endpoints {
        static let users = "/users"
        static func user(_ id: String) -> String { "/users/\(id)" }
        static func connections(userId: String) -> String { "/users/\(userId)/connections" }

        static func authorizeWhoop(userId: String) -> String {
            "/oauth/whoop/authorize?user_id=\(userId)"
        }

        static func recoverySummary(userId: String, startDate: String, endDate: String) -> String {
            "/users/\(userId)/summaries/recovery?start_date=\(startDate)&end_date=\(endDate)"
        }
        static func sleepSummary(userId: String, startDate: String, endDate: String) -> String {
            "/users/\(userId)/summaries/sleep?start_date=\(startDate)&end_date=\(endDate)"
        }
        static func activitySummary(userId: String, startDate: String, endDate: String) -> String {
            "/users/\(userId)/summaries/activity?start_date=\(startDate)&end_date=\(endDate)"
        }
        static func bodySummary(userId: String, startDate: String, endDate: String) -> String {
            "/users/\(userId)/summaries/body?start_date=\(startDate)&end_date=\(endDate)"
        }
        static func workouts(userId: String) -> String { "/users/\(userId)/events/workouts" }
        static func sleepEvents(userId: String) -> String { "/users/\(userId)/events/sleep" }

        static func triggerSync(provider: String, userId: String) -> String {
            "/providers/\(provider)/users/\(userId)/sync"
        }
    }

    // MARK: - Sync / cache
    static let syncIntervalMinutes = 15
    static let cacheExpirationMinutes = 5
}

// MARK: - Secure storage keys
struct OpenWearablesKeys {
    static let apiKey = "open_wearables_api_key"
    static let userId = "open_wearables_user_id"
    static let lastSyncDate = "open_wearables_last_sync"
}
