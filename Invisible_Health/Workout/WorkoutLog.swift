import Foundation

/// A single heart-rate sample on the workout timeline (`t` = seconds since the
/// workout started). Logged roughly every `WorkoutSessionController` interval so
/// the post-workout graph is smooth without storing every 1 Hz reading.
struct HRSample: Codable, Hashable {
    let t: TimeInterval
    let bpm: Int
}

/// A "moment" captured when the user spoke to the coach during a workout: the
/// transcript, the coach's expert read of how they were breathing/speaking, and
/// the heart rate at that instant. `t` = seconds since workout start, so it
/// lines up with the HR series on the graph.
struct WorkoutMoment: Codable, Identifiable, Hashable {
    var id = UUID()
    let t: TimeInterval
    let bpm: Int?
    let transcript: String
    let analysis: String
}

/// One recorded workout: the full HR series plus the spoken moments. Persisted
/// locally so you can review the graph + markers later.
struct WorkoutLog: Codable, Identifiable, Hashable {
    var id = UUID()
    let start: Date
    let end: Date
    let hr: [HRSample]
    let moments: [WorkoutMoment]

    var duration: TimeInterval { end.timeIntervalSince(start) }
    var peakBPM: Int? { hr.map(\.bpm).max() }
    var avgBPM: Int? { hr.isEmpty ? nil : hr.map(\.bpm).reduce(0, +) / hr.count }
}

/// Simple JSON-file store for workout logs (one file per workout under
/// Documents/workouts/). Good enough for solo dogfood; swap for Supabase later
/// to get cross-device history.
@MainActor
final class WorkoutStore: ObservableObject {
    static let shared = WorkoutStore()

    @Published private(set) var logs: [WorkoutLog] = []

    private let dir: URL = {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let d = base.appendingPathComponent("workouts", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    init() { reload() }

    func reload() {
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder()
        logs = files
            .filter { $0.pathExtension == "json" }
            .compactMap { try? decoder.decode(WorkoutLog.self, from: Data(contentsOf: $0)) }
            .sorted { $0.start > $1.start }
    }

    func save(_ log: WorkoutLog) {
        guard let data = try? JSONEncoder().encode(log) else { return }
        try? data.write(to: dir.appendingPathComponent("\(log.id.uuidString).json"))
        logs.insert(log, at: 0)
    }
}
