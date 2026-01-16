import Foundation
import CoreLocation
import ActivityKit
import SwiftUI // For Image handling maybe? No, UIImage is UIKit but SwiftUI might be needed for Activity types. Actually ActivityKit is enough but UIImage needs UIKit.

import UIKit // Explicitly needed for UIImage

class AgentManager: ObservableObject {
    static let shared = AgentManager()
    
    // The URL of your deployed Cloud Function
    // NOTE: In production, user_id should be dynamic. For MVP, we use a fixed ID.
    private let agentURL = "https://us-central1-gen-lang-client-0009721575.cloudfunctions.net/run-agent"
    
    @Published var lastDecision: String = "Agent is sleeping..."
    @Published var isLoading: Bool = false
    
    func triggerAgentCheck(userId: String = "test_user_1", location: CLLocationCoordinate2D? = nil) {
        guard var components = URLComponents(string: agentURL) else { return }
        
        var queryItems = [URLQueryItem(name: "user_id", value: userId)]
        
        // Add Location if available (The "Eyes")
        if let loc = location {
            queryItems.append(URLQueryItem(name: "lat", value: "\(loc.latitude)"))
            queryItems.append(URLQueryItem(name: "lng", value: "\(loc.longitude)"))
        }
        
        components.queryItems = queryItems
        
        guard let url = components.url else { return }
        
        print("🤖 calling Agent: \(url.absoluteString)")
        
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
                do {
                    // 1. Try to decode JSON
                    if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                        let message = json["message"] as? String ?? "Done"
                        let calories = json["calories"] as? Int ?? 0
                        
                        DispatchQueue.main.async {
                            print("🤖 Agent Response: \(message) | Calories: \(calories)")
                            self.lastDecision = message
                        }
                        
                        // 2. Update Live Activity (if calories > 0)
                        if calories > 0 {
                            for activity in Activity<NutritionActivityAttributes>.activities {
                                var updatedState = activity.content.state
                                updatedState.caloriesRemaining -= calories
                                updatedState.lastUpdated = Date()
                                await activity.update(ActivityContent(state: updatedState, staleDate: nil))
                                print("🔥 Live Activity Updated: - \(calories) kcal")
                            }
                        }
                    }
                    // Fallback: Just String
                    else if let responseString = String(data: data, encoding: .utf8) {
                        DispatchQueue.main.async {
                            self.lastDecision = responseString
                        }
                    }
                } catch {
                     print("JSON Decode Error: \(error)")
                }
            }
        }
        task.resume()
    }
    
    // MARK: - Phase B: Session Management
    
    func wakeUpAgent(userId: String = "test_user_1", fcmToken: String? = nil) {
        // Construct URL for 'wake_up' action
        guard var components = URLComponents(string: agentURL) else { return }
        var queryItems = [
            URLQueryItem(name: "user_id", value: userId),
            URLQueryItem(name: "action", value: "wake_up")
        ]
        if let token = fcmToken {
            queryItems.append(URLQueryItem(name: "fcm_token", value: token))
        }
        components.queryItems = queryItems
        
        guard let url = components.url else { return }
        
        print("☀️ Waking Up Agent: \(url.absoluteString)")
        
        URLSession.shared.dataTask(with: url) { _, _, _ in
            DispatchQueue.main.async {
                self.lastDecision = "Agent is Awake & Watching 👁️"
                print("✅ Agent Woke Up")
            }
        }.resume()
    }
    
    func sendHeartbeat(userId: String = "test_user_1") {
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
    
    func sendMultimodalInput(text: String?, image: UIImage?, audioURL: URL? = nil, userId: String = "test_user_1", completion: @escaping (String) -> Void) {
        guard let url = URL(string: agentURL) else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var body: [String: Any] = ["user_id": userId]
        
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
                do {
                    if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                        let message = json["message"] as? String ?? "Done"
                        let calories = json["calories"] as? Int ?? 0
                        
                        DispatchQueue.main.async {
                            // Update Live Activity if needed
                             if calories > 0 {
                                self.updateLiveActivity(calories: calories)
                            }
                        }
                        completion(message)
                    }
                } catch {
                    // Fallback to raw string
                    let str = String(data: data, encoding: .utf8) ?? "Done"
                    completion(str)
                }
            }
        }.resume()
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
        let calories: Int
        let protein: Int
        let carbs: Int
        let fats: Int
        let created_at: String
        
        // Helper to format Date
        var formattedDate: String {
            // Placeholder: Parse "2023-10-27T..." or rely on String
            return created_at.prefix(10).description 
        }
    }
    
    func fetchLogs(userId: String = "test_user_1", completion: @escaping ([NutritionLog]) -> Void) {
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
    
    func fetchSOSStrategies(userId: String = "test_user_1", completion: @escaping ([AgentSOSStrategy]) -> Void) {
        // Construct 'sos' action
        guard var components = URLComponents(string: agentURL) else { return }
        components.queryItems = [
            URLQueryItem(name: "user_id", value: userId),
            URLQueryItem(name: "action", value: "sos")
        ]
        
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
                    DispatchQueue.main.async { completion([]) }
                }
            } else {
                DispatchQueue.main.async { completion([]) }
            }
        }.resume()
    }
}
