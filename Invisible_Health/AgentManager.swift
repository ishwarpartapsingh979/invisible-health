//
//  AgentManager.swift
//  Invisible_Health
//
//  Created by Ishwar Partap Singh on 05/01/26.
//

import Foundation
import CoreLocation
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
}
