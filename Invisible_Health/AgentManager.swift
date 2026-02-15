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
    @Published var lastVideoURL: String? = nil
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
                  if let data = UserDefaults.standard.data(forKey: "user_goals"),
                     let goals = try? JSONDecoder().decode([Goal].self, from: data), !goals.isEmpty {
                      
                      let goalDescriptions = goals.map { goal -> String in
                          if let target = goal.targetDate {
                               let formatter = DateFormatter()
                               formatter.dateStyle = .medium
                               return "\(goal.title) (Deadline: \(formatter.string(from: target)))"
                          } else {
                              return "\(goal.title) (Ongoing)"
                          }
                      }.joined(separator: "; ")
                      
                      combinedLogs += "\n[GOAL_CONTEXT]: Active Goals: \(goalDescriptions)."
                  } else if let goalName = UserDefaults.standard.string(forKey: "goal_name") {
                      // Fallback for migration if not yet run
                      combinedLogs += "\n[GOAL_CONTEXT]: Target Event: \(goalName)."
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
                        
                        if let data = data, let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                            let message = json["message"] as? String ?? "Analysis complete."
                            let video = json["video_url"] as? String
                            
                            DispatchQueue.main.async { 
                                self.lastDecision = message 
                                self.lastVideoURL = video
                                completion(message)
                            }
                        } else {
                             // Fallback: Return raw string if JSON parsing fails
                             if let data = data, let rawResponse = String(data: data, encoding: .utf8) {
                                 print("⚠️ Analysis JSON Parse Failed. Raw: \(rawResponse)")
                                 completion(rawResponse)
                             } else {
                                 completion("Analysis received (No Data).")
                             }
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
    
    // MARK: - Recommendation Tab

    struct WorkoutRecommendation: Codable {
        let readiness_score: Int
        let readiness_label: String
        let readiness_color: String
        let recommended_workout_type: String
        let recommended_duration_min: Int
        let recommended_intensity: String
        let headline: String
        let reasoning: String
        let key_signals: [RecommendationSignal]
        let one_drill: String
        let logic_breakdown: [String]
    }

    struct RecommendationSignal: Codable, Identifiable {
        var id: String { label }
        let label: String
        let value: String
        let status: String // "good" | "warning" | "critical"
    }

    func fetchWorkoutRecommendation(userId: String = "00000000-0000-0000-0000-000000000001",
                                    completion: @escaping (WorkoutRecommendation?) -> Void) {
        let group = DispatchGroup()

        // Gather all signals in parallel
        var snapshot = HealthManager.ReadinessSnapshot(
            hrv: nil, restingHR: nil, vo2Max: nil, bodyMassKg: nil,
            timeInBedHours: 0, timeAsleepHours: 0,
            walkingAsymmetryPct: nil, morningHRStream: [],
            heartRateRecovery: nil
        )
        var telemetryGap: HealthManager.TelemetryGapResult? = nil
        var orthoSpike: HealthManager.OrthostasisResult? = nil
        var lastWorkout: HKWorkout? = nil
        var recentWorkouts: [HKWorkout] = []
        var steps: Double = 0

        group.enter()
        HealthManager.shared.fetchReadinessSnapshot { s in
            snapshot = s; group.leave()
        }

        group.enter()
        HealthManager.shared.calculateTelemetryGapSleep { gap in
            telemetryGap = gap; group.leave()
        }

        group.enter()
        HealthManager.shared.fetchRecentWorkouts(days: 2) { workouts in
            recentWorkouts = workouts
            lastWorkout = workouts.first
            group.leave()
        }

        group.enter()
        HealthManager.shared.fetchTodaySteps { s in
            steps = s; group.leave()
        }

        group.notify(queue: .main) {
            // Orthostatic spike uses watchOnTime from telemetry gap
            if let watchOn = telemetryGap?.watchOnTime {
                group.enter()
                HealthManager.shared.calculateOrthostaticSpike(from: watchOn) { spike in
                    orthoSpike = spike; group.leave()
                }
                group.notify(queue: .main) {
                    self.sendRecommendationToBackend(
                        userId: userId, snapshot: snapshot,
                        telemetryGap: telemetryGap, orthoSpike: orthoSpike,
                        lastWorkout: lastWorkout, recentWorkouts: recentWorkouts, steps: steps,
                        completion: completion
                    )
                }
            } else {
                self.sendRecommendationToBackend(
                    userId: userId, snapshot: snapshot,
                    telemetryGap: telemetryGap, orthoSpike: nil,
                    lastWorkout: lastWorkout, recentWorkouts: recentWorkouts, steps: steps,
                    completion: completion
                )
            }
        }
    }

    private func sendRecommendationToBackend(
        userId: String,
        snapshot: HealthManager.ReadinessSnapshot,
        telemetryGap: HealthManager.TelemetryGapResult?,
        orthoSpike: HealthManager.OrthostasisResult?,
        lastWorkout: HKWorkout?,
        recentWorkouts: [HKWorkout],
        steps: Double,
        completion: @escaping (WorkoutRecommendation?) -> Void
    ) {
        guard let url = URL(string: agentURL) else { completion(nil); return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Load goals from UserDefaults
        var activeGoals: [String] = []
        if let data = UserDefaults.standard.data(forKey: "user_goals"),
           let goals = try? JSONDecoder().decode([Goal].self, from: data) {
            activeGoals = goals.map { goal in
                if let target = goal.targetDate {
                    let f = DateFormatter(); f.dateStyle = .medium
                    return "\(goal.title) (by \(f.string(from: target)))"
                }
                return goal.title
            }
        }

        // Diet rating for today
        let dietRating = NotificationManager.dietRating(for: NotificationManager.todayDateString()) ?? "unknown"

        // Split workouts into today vs yesterday
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday)!

        let todayWorkouts = recentWorkouts.filter { $0.startDate >= startOfToday }
        let yesterdayWorkouts = recentWorkouts.filter { $0.startDate >= startOfYesterday && $0.startDate < startOfToday }

        func workoutSummary(_ workouts: [HKWorkout]) -> String {
            guard !workouts.isEmpty else { return "None" }
            return workouts.map { w in
                let name = HKWorkoutActivityType(rawValue: w.workoutActivityType.rawValue)?.name ?? "Workout"
                let mins = Int(w.duration / 60)
                let cals = Int(w.statistics(for: HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!)?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0)
                return "\(name) \(mins)min \(cals)kcal"
            }.joined(separator: ", ")
        }

        func totalCals(_ workouts: [HKWorkout]) -> Int {
            workouts.reduce(0) { sum, w in
                sum + Int(w.statistics(for: HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!)?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0)
            }
        }

        let todaySummary = workoutSummary(todayWorkouts)
        let yesterdaySummary = workoutSummary(yesterdayWorkouts)
        let yesterdayTotalCals = totalCals(yesterdayWorkouts)

        // Keep last_workout for backward compat (most recent overall)
        let lastWorkoutName = lastWorkout.map { HKWorkoutActivityType(rawValue: $0.workoutActivityType.rawValue)?.name ?? "Workout" } ?? "None"
        let lastWorkoutDuration = Int((lastWorkout?.duration ?? 0) / 60)
        let lastWorkoutCals = Int(lastWorkout?.statistics(for: HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!)?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0)

        var body: [String: Any] = [
            "action":                       "workout_recommendation",
            "user_id":                      userId,
            "steps_today":                  Int(steps),
            "diet_rating":                  dietRating,
            "active_goals":                 activeGoals,
            "last_workout_name":            lastWorkoutName,
            "last_workout_duration_min":    lastWorkoutDuration,
            "last_workout_calories":        lastWorkoutCals,
            "today_workouts":               todaySummary,
            "yesterday_workouts":           yesterdaySummary,
            "yesterday_total_calories":     yesterdayTotalCals
        ]

        // HRV, RHR, VO2, body mass, HRR
        if let v = snapshot.hrv             { body["hrv"] = v }
        if let v = snapshot.restingHR       { body["rhr"] = v }
        if let v = snapshot.vo2Max          { body["vo2_max"] = v }
        if let v = snapshot.bodyMassKg      { body["body_mass_kg"] = v }
        if let v = snapshot.heartRateRecovery { body["hrr_1min"] = v }
        if let v = snapshot.walkingAsymmetryPct { body["walking_asymmetry_pct"] = v }

        // Sleep
        if let gap = telemetryGap {
            body["proxy_sleep_hours"]   = gap.proxyTimeInBed / 3600
            body["iphone_in_bed_hours"] = gap.iPhoneInBedSeconds / 3600
        }

        // Orthostatic spike
        if let spike = orthoSpike {
            body["ortho_avg_bpm"]  = spike.averageBPM
            body["ortho_peak_bpm"] = spike.peakBPM
        }

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        } catch {
            print("❌ Recommendation encode error: \(error)"); completion(nil); return
        }

        print("🎯 Fetching workout recommendation...")

        URLSession.shared.dataTask(with: request) { data, _, error in
            guard let data = data, error == nil else {
                DispatchQueue.main.async { completion(nil) }; return
            }
            do {
                let rec = try JSONDecoder().decode(WorkoutRecommendation.self, from: data)
                DispatchQueue.main.async { completion(rec) }
            } catch {
                print("❌ Recommendation decode error: \(error)")
                if let raw = String(data: data, encoding: .utf8) { print("Raw: \(raw)") }
                DispatchQueue.main.async { completion(nil) }
            }
        }.resume()
    }

    // MARK: - Tomorrow Preview

    struct TomorrowPreview: Codable {
        let preview_workout_type: String
        let preview_duration_range: String
        let preview_intensity_ceiling: String
        let preview_headline: String
        let preview_reasoning: String
        let caveat: String
    }

    /// Cached tomorrow preview — set as soon as diet rating is saved.
    /// RecommendationView reads this directly.
    @Published var cachedTomorrowPreview: TomorrowPreview? = nil

    /// Cached morning recommendation — set after morning audit completes.
    @Published var cachedMorningRecommendation: WorkoutRecommendation? = nil

    func fetchTomorrowPreview(dietRating: String,
                              userId: String = "00000000-0000-0000-0000-000000000001",
                              completion: ((TomorrowPreview?) -> Void)? = nil) {
        // Fetch last workout for context, then hit backend
        HealthManager.shared.fetchRecentWorkouts(days: 2) { [weak self] workouts in
            guard let self = self else { return }
            let last = workouts.first
            let name     = last.map { HKWorkoutActivityType(rawValue: $0.workoutActivityType.rawValue)?.name ?? "Workout" } ?? "None"
            let duration = Int((last?.duration ?? 0) / 60)
            let cals     = Int(last?.statistics(for: HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!)?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0)

            guard let url = URL(string: self.agentURL) else { completion?(nil); return }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let body: [String: Any] = [
                "action":                    "tomorrow_preview",
                "user_id":                   userId,
                "diet_rating":               dietRating,
                "last_workout_name":         name,
                "last_workout_duration_min": duration,
                "last_workout_calories":     cals
            ]

            guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else {
                completion?(nil); return
            }
            request.httpBody = httpBody

            print("🔮 Fetching tomorrow preview for diet rating: \(dietRating)")

            URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
                guard let self = self, let data = data, error == nil else {
                    DispatchQueue.main.async { completion?(nil) }; return
                }
                do {
                    let preview = try JSONDecoder().decode(TomorrowPreview.self, from: data)
                    DispatchQueue.main.async {
                        self.cachedTomorrowPreview = preview
                        completion?(preview)
                    }
                } catch {
                    print("❌ TomorrowPreview decode error: \(error)")
                    DispatchQueue.main.async { completion?(nil) }
                }
            }.resume()
        }
    }

    // MARK: - Phase 6.3: Contextual Chat
    

    
    func chatWithCoach(workout: HKWorkout, history: [[String: String]], completion: @escaping (String) -> Void) {
        HealthManager.shared.fetchComprehensiveWorkoutData(workout: workout) { metrics in
            
            var body: [String: Any] = [
                "action": "chat_with_coach",
                "user_id": "00000000-0000-0000-0000-000000000001",
                "history": history,
                "metrics": metrics
            ]
            
            guard let url = URL(string: self.agentURL) else { return }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
            } catch {
                print("❌ JSON Error: \(error)")
                completion("Error encoding.")
                return 
            }
            
            URLSession.shared.dataTask(with: request) { data, _, error in
                if let data = data, let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                    let message = json["message"] as? String ?? "I'm not sure."
                    DispatchQueue.main.async { completion(message) }
                } else {
                    DispatchQueue.main.async { completion("Coach is unresponsive.") }
                }
            }.resume()
        }
    }
}
