import Foundation
import CoreLocation
import ActivityKit
import SwiftUI
import UIKit
import HealthKit

class AgentManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = AgentManager()
    
    // The URL of your deployed Cloud Function
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
    }
    
    // Use a Valid UUID for Supabase
    func triggerAgentCheck(userId: String = "00000000-0000-0000-0000-000000000001", location: CLLocationCoordinate2D? = nil) {
        // Fetch Steps
        HealthManager.shared.fetchTodaySteps { steps in
            guard var components = URLComponents(string: self.agentURL) else { return }
            
            var queryItems = [
                URLQueryItem(name: "user_id", value: userId),
                URLQueryItem(name: "steps", value: "\(Int(steps))")
            ]
            
            // Add Location if available
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
                    self.handleAgentResponse(data) { _ in }
                }
            }
            task.resume()
        }
    }
    
    // MARK: - Phase B: Session Management
    
    func wakeUpAgent(userId: String = "00000000-0000-0000-0000-000000000001", fcmToken: String? = nil) {
        HealthManager.shared.fetchTodaySteps { steps in
            guard var components = URLComponents(string: self.agentURL) else { return }
            var queryItems = [
                URLQueryItem(name: "user_id", value: userId),
                URLQueryItem(name: "action", value: "wake_up"),
                URLQueryItem(name: "steps", value: "\(Int(steps))")
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
        guard var components = URLComponents(string: agentURL) else { return }
        components.queryItems = [
            URLQueryItem(name: "user_id", value: userId),
            URLQueryItem(name: "action", value: "heartbeat")
        ]
        
        guard let url = components.url else { return }
        print("💓 Sending Heartbeat: \(url.absoluteString)")
        URLSession.shared.dataTask(with: url).resume()
    }
    
    // MARK: - Phase C: Multimodal Chat
    
    func sendMultimodalInput(text: String?, image: UIImage?, audioURL: URL? = nil, userId: String = "00000000-0000-0000-0000-000000000001", completion: @escaping (String) -> Void) {
        guard let url = URL(string: agentURL) else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var body: [String: Any] = ["user_id": userId]
        
        // Add Location
        if let loc = self.currentLocation {
            body["lat"] = loc.latitude
            body["lng"] = loc.longitude
        }
        
        if let text = text, !text.isEmpty {
            body["text"] = text
        }
        
        if let image = image {
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
                body["audio_data"] = base64String
                body["mime_type"] = "audio/mp4"
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
            "user_id": "00000000-0000-0000-0000-000000000001",
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
    
    // Helper to Handle Agent Response
    private func handleAgentResponse(_ data: Data, completion: @escaping (String) -> Void) {
        do {
            if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                let message = json["message"] as? String ?? "Done"
                let calories = json["calories"] as? Int ?? 0
                
                let protein = json["protein"] as? Double
                let carbs = json["carbs"] as? Double
                let fat = json["fats"] as? Double
                
                DispatchQueue.main.async {
                    self.lastDecision = message
                    print("🤖 Agent Response: \(message) | Calories: \(calories)")
                    
                    if let debugInfo = json["_debug"] as? String {
                        print("📡 Backend Debug: \(debugInfo)")
                    }
                    
                    if calories > 0 {
                        self.updateLiveActivity(calories: calories)
                         NotificationManager.shared.shortNotification(
                            title: "✅ Logged: \(Int(calories)) kcal",
                            body: message
                        )
                    }
                    
                    HealthManager.shared.logDietaryData(
                        calories: Double(calories),
                        protein: protein,
                        carbs: carbs,
                        fat: fat
                    )
                }
                
                completion(message)
            } else {
                 let str = String(data: data, encoding: .utf8) ?? "Done"
                 DispatchQueue.main.async { self.lastDecision = str }
                 completion(str)
            }
        } catch {
            print("❌ JSON Decode Error: \(error)")
            if let str = String(data: data, encoding: .utf8) {
                print("📝 WakeUp Mismatch Raw Data: \(str)")
            }
            completion("Error")
        }
    }

    // Helper to update Live Activity
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
        let calories: Double?
        let protein: Double?
        let carbs: Double?
        let fats: Double?
        let message: String?
        let created_at: String
        
        var formattedDate: String {
            return created_at.prefix(10).description 
        }
    }
    
    func fetchLogs(userId: String = "00000000-0000-0000-0000-000000000001", completion: @escaping ([NutritionLog]) -> Void) {
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
                    DispatchQueue.main.async { completion([]) }
                }
            } else {
                DispatchQueue.main.async { completion([]) }
            }
        }.resume()
    }
    
    // MARK: - Phase E: SOS Strategies
    
    struct AgentSOSStrategy: Codable, Identifiable {
        let id = UUID()
        let title: String
        let description: String
        let icon: String
        let color: String? // Optional because legacy data might not have it
        
        enum CodingKeys: String, CodingKey {
            case title, description, icon, color
        }
    }
    
    func fetchSOSStrategies(input: String? = nil, userId: String = "00000000-0000-0000-0000-000000000001", completion: @escaping ([AgentSOSStrategy]) -> Void) {
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
                    DispatchQueue.main.async { completion([]) }
                }
            } else {
                DispatchQueue.main.async { completion([]) }
            }
        }.resume()
    }
    // MARK: - Phase 3.1: Workout Analysis (Elite Coach)
    
    func analyzeWorkout(workout: HKWorkout? = nil, completion: @escaping (String) -> Void) {
        
        // Internal helper to process valid workout
        func process(_ targetWorkout: HKWorkout) {
             let group = DispatchGroup()
             
             // Metrics (Legacy Support containers)
             var osc: Double?; var gct: Double?; var pwr: Double?
             var avgHR: Double?; var maxHR: Double?
             
             // New Dynamic Metrics
             var comprehensiveMetricsJSON: String = "{}"
             
             // Logs
             var workoutLogs: String = ""
             
             group.enter()
             HealthManager.shared.fetchComprehensiveWorkoutData(workout: targetWorkout) { metrics in
                 // Populate Legacy
                 osc = metrics["avg_oscillation_cm"] as? Double
                 gct = metrics["avg_gct_ms"] as? Double
                 pwr = metrics["avg_power_watts"] as? Double
                 avgHR = metrics["avg_hr"] as? Double
                 maxHR = metrics["max_hr"] as? Double
                 
                 // Serialize Full Dict
                 if let jsonData = try? JSONSerialization.data(withJSONObject: metrics, options: []),
                    let jsonStr = String(data: jsonData, encoding: .utf8) {
                     comprehensiveMetricsJSON = jsonStr
                 }
                 group.leave()
             }
             
             group.enter()
             self.fetchLogs { allLogs in
                 // Filter logs created on the same day as the workout
                 let calendar = Calendar.current
                 let workoutDate = targetWorkout.startDate
                 let relevant = allLogs.filter { log in
                     let formatter = ISO8601DateFormatter()
                     if let logDate = formatter.date(from: log.created_at) {
                         return calendar.isDate(logDate, inSameDayAs: workoutDate)
                     }
                     return false
                 }
                 
                 var combinedLogs = ""
                 if !relevant.isEmpty {
                     combinedLogs = relevant.map { "\($0.food_name) (\($0.message ?? ""))" }.joined(separator: "; ")
                 }
                 
                 // Inject Goal Context
                 if let goalName = UserDefaults.standard.string(forKey: "goal_name"),
                    let goalDate = UserDefaults.standard.object(forKey: "goal_date") as? Date {
                     let formatter = DateFormatter()
                     formatter.dateStyle = .medium
                     let dateStr = formatter.string(from: goalDate)
                     combinedLogs += "\n[GOAL_CONTEXT]: Target Event: \(goalName) on \(dateStr)."
                 }
                 
                 workoutLogs = combinedLogs
                 group.leave()
             }
             
             group.notify(queue: .main) {
                 self.sendWorkoutToBackend(
                    workout: targetWorkout,
                    osc: osc, gct: gct, pwr: pwr, avgHR: avgHR, maxHR: maxHR,
                    logs: workoutLogs,
                    comprehensiveMetrics: comprehensiveMetricsJSON, // New Field
                    completion: completion
                 )
             }
        }
        
        if let w = workout {
            process(w)
        } else {
            // Fallback: Fetch Last Workout (Today)
            HealthManager.shared.fetchRecentWorkouts(days: 1) { workouts in
                guard let lastWorkout = workouts.first else {
                    completion("No workouts found for today.")
                    return
                }
                process(lastWorkout)
            }
        }
    }
    
    // Extracted Backend Call
    private func sendWorkoutToBackend(workout: HKWorkout, osc: Double?, gct: Double?, pwr: Double?, avgHR: Double?, maxHR: Double?, logs: String, comprehensiveMetrics: String, completion: @escaping (String) -> Void) {
        let lastWorkout = workout
                
                // 3. Prepare Payload
                guard var components = URLComponents(string: self.agentURL) else { return }
                
                // Encode basic workout stats
                let duration = lastWorkout.duration // TimeInterval
                let calories = lastWorkout.statistics(for: HKQuantityType.quantityType(forIdentifier: HKQuantityTypeIdentifier.activeEnergyBurned)!)?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
                
                // Note: We'd typically POST this JSON, but using GET query params for consistency with existing simple endpoints unless it gets too big.
                // Let's use POST for safety as this is data heavy.
                
                guard let url = URL(string: self.agentURL) else { return }
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                
                // Parse metrics back to dict for embedding (or just send string and parse on server -> let's embed as object if possible, but easier to send string 'metrics_json')
                // Actually better to send valid JSON object in body.
                // But Swift needs `Any`.
                
                var body: [String: Any] = [
                    "action": "analyze_workout",
                    "user_id": "00000000-0000-0000-0000-000000000001",
                    "workout_type": "\(lastWorkout.workoutActivityType.rawValue)",
                    "duration_seconds": duration,
                    "calories": calories,
                    "avg_oscillation_cm": osc ?? 0,
                    "avg_gct_ms": gct ?? 0,
                    "avg_power_watts": pwr ?? 0,
                    "avg_hr": avgHR ?? 0,
                    "max_hr": maxHR ?? 0,
                    "logs": logs
                ]
                
                // Add Metrics Dict
                if let data = comprehensiveMetrics.data(using: .utf8),
                   let jsonDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    body["metrics"] = jsonDict
                }
                
                do {
                    request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
                    
                    print("🏋️ sending Analysis Request: \(body)")
                    
                    // 4. Send
                    DispatchQueue.main.async { self.isLoading = true; self.lastDecision = "Analyzing Workout..." }
                    
                    URLSession.shared.dataTask(with: request) { data, response, error in
                        DispatchQueue.main.async { self.isLoading = false }
                        
                        if let error = error {
                            print("❌ Analysis Error: \(error)")
                            completion("Error analyzing.")
                            return
                        }
                        
                        if let data = data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                            let message = json["message"] as? String ?? "Analysis complete."
                            DispatchQueue.main.async { self.lastDecision = message }
                            completion(message)
                        } else {
                             completion("Analysis received.")
                        }
                    }.resume()
                    
                } catch {
                    print("❌ JSON Error")
                }
    }

    
    // MARK: - Phase 3.3: Nightly Holistic Report
    
    func generateDailyReport(completion: @escaping (String) -> Void) {
        // 1. Fetch Today's Data
        let group = DispatchGroup()
        
        var steps: Double = 0
        var workouts: [HKWorkout] = []
        var vo2: Double?
        var hrv: Double?
        var rhr: Double?
        var recentLogs: [NutritionLog] = []
        
        group.enter()
        HealthManager.shared.fetchTodaySteps { s in
            steps = s
            group.leave()
        }
        
        group.enter()
        HealthManager.shared.fetchRecentWorkouts(days: 1) { w in
            workouts = w
            group.leave()
        }
        
        group.enter()
        HealthManager.shared.fetchEliteBiometrics { v, h, r in
            vo2 = v
            hrv = h
            rhr = r
            group.leave()
        }
        
        group.enter()
        self.fetchLogs { logs in
            recentLogs = logs
            group.leave()
        }
        
        group.notify(queue: .main) {
            // Filter Logs for TODAY
            let todayLogs = recentLogs.filter { log in
                let formatter = ISO8601DateFormatter()
                if let date = formatter.date(from: log.created_at) {
                    return Calendar.current.isDateInToday(date)
                }
                return false
            }
            
            // 2. Build Payload
            guard let url = URL(string: self.agentURL) else { return }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let workoutSummary = workouts.map { $0.workoutActivityType.rawValue }.description
            
            // Simplify logs for payload to save tokens
            let logSummary = todayLogs.map { "\($0.food_name): \($0.calories ?? 0) kcal" }.joined(separator: ", ")
            
            let body: [String: Any] = [
                "action": "nightly_report",
                "user_id": "00000000-0000-0000-0000-000000000001",
                "steps": steps,
                "workouts": workoutSummary,
                "vo2": vo2 ?? 0,
                "hrv": hrv ?? 0,
                "rhr": rhr ?? 0,
                "logs": logSummary // Context for calories in
            ]
            
            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
                print("🌙 Sending Nightly Report Request: \(body)")
                
                DispatchQueue.main.async { self.isLoading = true; self.lastDecision = "Generating Nightly Report..." }
                
                URLSession.shared.dataTask(with: request) { data, response, error in
                    DispatchQueue.main.async { self.isLoading = false }
                    
                    if let error = error {
                        print("❌ Report Error: \(error)")
                        completion("Error generating report.")
                        return
                    }
                    
                    if let data = data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        let message = json["message"] as? String ?? "Report Generated."
                        DispatchQueue.main.async { self.lastDecision = message }
                        completion(message)
                    } else {
                         completion("Report received.")
                    }
                }.resume()
                
            } catch {
                print("❌ JSON Error")
            }
        }
    }
}
