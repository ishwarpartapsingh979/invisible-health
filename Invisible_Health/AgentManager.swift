import Foundation
import CoreLocation
import ActivityKit
import SwiftUI // For Image handling maybe? No, UIImage is UIKit but SwiftUI might be needed for Activity types. Actually ActivityKit is enough but UIImage needs UIKit.

import UIKit // Explicitly needed for UIImage

class AgentManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = AgentManager()
    
    // The URL of your deployed Cloud Function
    // NOTE: In production, user_id should be dynamic. For MVP, we use a fixed ID.
    private let agentURL = "https://us-central1-gen-lang-client-0009721575.cloudfunctions.net/run-agent"
    
    @Published var lastDecision: String = "Agent is sleeping..."
    @Published var isLoading: Bool = false
    
    // Location Manager (Phase 2.1)
    private let locationManager = CLLocationManager()
    @Published var currentLocation: CLLocationCoordinate2D?
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }
    
    // MARK: - CLLocationManagerDelegate
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        self.currentLocation = loc.coordinate
        // print("📍 Location Updated: \(loc.coordinate.latitude), \(loc.coordinate.longitude)")
    }
    
    // Use a Valid UUID for Supabase (v4 placeholder)
    func triggerAgentCheck(userId: String = "00000000-0000-0000-0000-000000000001", location: CLLocationCoordinate2D? = nil) {
        // Fetch Steps (Phase F)
        HealthManager.shared.fetchTodaySteps { steps in
            guard var components = URLComponents(string: self.agentURL) else { return }
            
            var queryItems = [
                URLQueryItem(name: "user_id", value: userId),
                URLQueryItem(name: "steps", value: "\(Int(steps))")
            ]
            
            // Add Location if available (The "Eyes")
            if let loc = location {
                queryItems.append(URLQueryItem(name: "lat", value: "\(loc.latitude)"))
                queryItems.append(URLQueryItem(name: "lng", value: "\(loc.longitude)"))
            }
            
            components.queryItems = queryItems
            
            guard let url = components.url else { return }
            
            print("🤖 Calling Agent (Steps: \(Int(steps))): \(url.absoluteString)")
            
            DispatchQueue.main.async {
                self.isLoading = true
                self.lastDecision = "Thinking... 🧠"
            }
            
            let task = URLSession.shared.dataTask(with: url) { data, response, error in
                DispatchQueue.main.async {
                    self.isLoading = false
                }
                
                if let error = error {
                    DispatchQueue.main.async {
                        self.lastDecision = "Error: \(error.localizedDescription)"
                    }
                    return
                }
                
                if let data = data {
                    // Use Centralized Helper (Phase F)
                    self.handleAgentResponse(data) { _ in }
                }
            }
            task.resume()
        }
    }
    
    // MARK: - Phase B: Session Management
    
    func wakeUpAgent(userId: String = "00000000-0000-0000-0000-000000000001", fcmToken: String? = nil) {
        // Fetch Steps first (Phase F)
        HealthManager.shared.fetchTodaySteps { steps in
            // Construct URL for 'wake_up' action
            guard var components = URLComponents(string: self.agentURL) else { return }
            var queryItems = [
                URLQueryItem(name: "user_id", value: userId),
                URLQueryItem(name: "action", value: "wake_up"),
                URLQueryItem(name: "steps", value: "\(Int(steps))") // Add Steps
            ]
            if let token = fcmToken {
                queryItems.append(URLQueryItem(name: "fcm_token", value: token))
            }
            components.queryItems = queryItems
            
            guard let url = components.url else { return }
            
            print("☀️ Waking Up Agent (Steps: \(Int(steps))): \(url.absoluteString)")
            
            URLSession.shared.dataTask(with: url) { _, _, _ in
                DispatchQueue.main.async {
                    self.lastDecision = "Agent is Awake & Watching 👁️"
                    print("✅ Agent Woke Up")
                }
            }.resume()
        }
    }
    
    func sendHeartbeat(userId: String = "00000000-0000-0000-0000-000000000001") {
        // Construct URL for 'heartbeat' action
        guard var components = URLComponents(string: agentURL) else { return }
        components.queryItems = [
            URLQueryItem(name: "user_id", value: userId),
            URLQueryItem(name: "action", value: "heartbeat")
        ]
        
        guard let url = components.url else { return }
        
        print("💓 Sending Heartbeat: \(url.absoluteString)")
        
        print("💓 Sending Heartbeat: \(url.absoluteString)")
        
        URLSession.shared.dataTask(with: url).resume()
    }
    
    // MARK: - Phase C: Multimodal Chat
    
    // MARK: - Phase C: Multimodal Chat
    
    func sendMultimodalInput(text: String?, image: UIImage?, audioURL: URL? = nil, userId: String = "00000000-0000-0000-0000-000000000001", completion: @escaping (String) -> Void) {
        guard let url = URL(string: agentURL) else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var body: [String: Any] = ["user_id": userId]
        
        // Phase 2.1: Add Location "The Eyes"
        if let loc = self.currentLocation {
            body["lat"] = loc.latitude
            body["lng"] = loc.longitude
        }
        
        if let text = text, !text.isEmpty {
            body["text"] = text
        }
        
        if let image = image {
            // Compress and Encode
            if let imageData = image.jpegData(compressionQuality: 0.7) {
                let base64String = imageData.base64EncodedString()
                body["image_data"] = base64String
                body["mime_type"] = "image/jpeg"
            }
        }
        
        if let audioURL = audioURL {
            do {
                let audioData = try Data(contentsOf: audioURL)
                let base64String = audioData.base64EncodedString()
                // Send as audio_data key
                body["audio_data"] = base64String
                body["mime_type"] = "audio/mp4" // Gemini handles m4a/aac as mp4 container usually
            } catch {
                print("❌ Audio Read Error: \(error)")
            }
        }
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        } catch {
            print("❌ JSON Encode Error: \(error)")
            completion("Error sending data")
            return
        }
        
        DispatchQueue.main.async {
            self.isLoading = true
            self.lastDecision = "Analyzing..."
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                self.isLoading = false
            }
            
            if let error = error {
                print("❌ Network Error: \(error)")
                completion("Error: \(error.localizedDescription)")
                return
            }
            
            if let data = data {
                // Use Centralized Helper (Phase F)
                self.handleAgentResponse(data, completion: completion)
            }
        }.resume()
    }
    
    // MARK: - Phase H: Editing Logs
    
    func updateLog(_ log: NutritionLog) {
        guard let url = URL(string: agentURL) else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "action": "update_log",
            "user_id": "00000000-0000-0000-0000-000000000001", // Default Session User
            "id": log.id,
            "food_name": log.food_name,
            "calories": log.calories ?? 0,
            "protein": log.protein ?? 0,
            "carbs": log.carbs ?? 0,
            "fats": log.fats ?? 0,
            "message": log.message ?? ""
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
            
            print("✏️ Updating Log: \(log.food_name)")
            
            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    print("❌ Error updating log: \(error)")
                    return
                }
                
                if let data = data, let str = String(data: data, encoding: .utf8) {
                    print("✅ Backend Update Response: \(str)")
                }
            }.resume()
            
        } catch {
            print("❌ Error encoding update: \(error)")
        }
    }
    
    // Helper to Handle Agent Response (Centralized)
    private func handleAgentResponse(_ data: Data, completion: @escaping (String) -> Void) {
        do {
            if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                let message = json["message"] as? String ?? "Done"
                let calories = json["calories"] as? Int ?? 0
                
                // Parse Macros (Phase F)
                let protein = json["protein"] as? Double
                let carbs = json["carbs"] as? Double
                let fat = json["fats"] as? Double // Note: Backend returns 'fats'
                
                DispatchQueue.main.async {
                    // Update UI
                    self.lastDecision = message
                    print("🤖 Agent Response: \(message) | Calories: \(calories)")
                    
                    // -- DEBUG: Trace Backend Logs --
                    if let debugInfo = json["_debug"] as? String {
                        print("📡 Backend Debug: \(debugInfo)")
                    }
                    
                    // Update Live Activity
                    if calories > 0 {
                        self.updateLiveActivity(calories: calories)
                        
                        // ✅ Phase 2.1: Instant Notification
                         NotificationManager.shared.shortNotification(
                            title: "✅ Logged: \(Int(calories)) kcal",
                            body: message
                        )
                    }
                    
                    // Sync to HealthKit (Phase F)
                    HealthManager.shared.logDietaryData(
                        calories: Double(calories),
                        protein: protein,
                        carbs: carbs,
                        fat: fat
                    )
                }
                
                completion(message)
            } else {
                 // Fallback
                 let str = String(data: data, encoding: .utf8) ?? "Done"
                 DispatchQueue.main.async { self.lastDecision = str }
                 completion(str)
            }
        } catch {
            print("❌ JSON Decode Error: \(error)")
            // Debug Raw Data (e.g. if Backend returned 500 HTML)
            if let str = String(data: data, encoding: .utf8) {
                print("📝 WakeUp Mismatch Raw Data: \(str)")
            }
            completion("Error")
        }
    }

    // Helper to update Live Activity (reused code)
    private func updateLiveActivity(calories: Int) {
         Task {
            for activity in Activity<NutritionActivityAttributes>.activities {
                var updatedState = activity.content.state
                updatedState.caloriesRemaining -= calories
                updatedState.lastUpdated = Date()
                await activity.update(ActivityContent(state: updatedState, staleDate: nil))
            }
         }
    }
    
    // MARK: - Phase D: Data Feed
    
    struct NutritionLog: Codable, Identifiable {
        let id: String
        let food_name: String
        let calories: Double? // Changed to Optional Double
        let protein: Double?  // Changed to Optional Double
        let carbs: Double?    // Changed to Optional Double
        let fats: Double?     // Changed to Optional Double
        let message: String?  // AI Commentary
        let created_at: String
        
        // Helper to format Date
        var formattedDate: String {
            // Placeholder: Parse "2023-10-27T..." or rely on String
            return created_at.prefix(10).description 
        }
    }
    
    func fetchLogs(userId: String = "00000000-0000-0000-0000-000000000001", completion: @escaping ([NutritionLog]) -> Void) {
        // Construct 'get_logs' action
        guard var components = URLComponents(string: agentURL) else { return }
        components.queryItems = [
            URLQueryItem(name: "user_id", value: userId),
            URLQueryItem(name: "action", value: "get_logs")
        ]
        
        guard let url = components.url else { return }
        
        print("📥 Fetching Logs: \(url.absoluteString)")
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            if let data = data {
                do {
                    let logs = try JSONDecoder().decode([NutritionLog].self, from: data)
                    DispatchQueue.main.async {
                        completion(logs)
                    }
                } catch {
                    print("❌ Error decoding logs: \(error)")
                    // Debug Raw Data
                    if let str = String(data: data, encoding: .utf8) {
                        print("Raw Data: \(str)")
                    }
                    DispatchQueue.main.async { completion([]) }
                }
            } else {
                DispatchQueue.main.async { completion([]) }
            }
        }.resume()
    }
    
    // MARK: - Phase E: SOS Strategies
    
    struct AgentSOSStrategy: Codable, Identifiable {
        let id = UUID() // Local ID
        let title: String
        let description: String
        let icon: String // SF Symbol
        let color: String // "blue", "red", etc.
        
        // CodingKeys to ignore ID which isn't in JSON
        enum CodingKeys: String, CodingKey {
            case title, description, icon, color
        }
    }
    
    func fetchSOSStrategies(input: String? = nil, userId: String = "00000000-0000-0000-0000-000000000001", completion: @escaping ([AgentSOSStrategy]) -> Void) {
        // Construct 'sos' action
        guard var components = URLComponents(string: agentURL) else { return }
        
        var queryItems = [
            URLQueryItem(name: "user_id", value: userId),
            URLQueryItem(name: "action", value: "sos")
        ]
        
        if let input = input, !input.isEmpty {
            queryItems.append(URLQueryItem(name: "input", value: input))
        }
        
        components.queryItems = queryItems
        
        guard let url = components.url else { return }
        
        print("🚑 Fetching SOS: \(url.absoluteString)")
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            if let data = data {
                do {
                    let strategies = try JSONDecoder().decode([AgentSOSStrategy].self, from: data)
                    DispatchQueue.main.async {
                        completion(strategies)
                    }
                } catch {
                    print("❌ Error decoding SOS: \(error)")
                    if let str = String(data: data, encoding: .utf8) {
                        print("📝 JSON Mismatch Raw Data: \(str)")
                    }
                    DispatchQueue.main.async { completion([]) }
                }
            } else {
                DispatchQueue.main.async { completion([]) }
            }
        }.resume()
    }
}
