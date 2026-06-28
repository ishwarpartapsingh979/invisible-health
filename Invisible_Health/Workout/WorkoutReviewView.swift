import SwiftUI
import Charts

/// Post-workout review: the full heart-rate graph with markers at each spoken
/// moment. Tap a moment card to highlight it on the graph and read what you said
/// + the coach's breathing analysis at that heart rate.
struct WorkoutReviewView: View {
    let log: WorkoutLog
    @State private var selected: WorkoutMoment?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                summary
                if log.hr.isEmpty {
                    placeholder("No heart-rate data was recorded for this workout.")
                } else {
                    chart
                }

                if log.moments.isEmpty {
                    placeholder("No spoken moments. Say “Hey Coach” during a workout and talk — each time gets pinned here with how you sounded.")
                } else {
                    Text("MOMENTS").font(.caption).fontWeight(.semibold).tracking(2).foregroundColor(.gray)
                    ForEach(log.moments) { momentCard($0) }
                }
            }
            .padding()
        }
        .navigationTitle(log.start.formatted(date: .abbreviated, time: .shortened))
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Summary

    private var summary: some View {
        HStack(spacing: 18) {
            stat(fmtDuration(log.duration), "Duration")
            if let a = log.avgBPM { stat("\(a)", "Avg HR") }
            if let p = log.peakBPM { stat("\(p)", "Peak HR") }
            stat("\(log.moments.count)", "Moments")
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.weight(.bold)).monospacedDigit()
            Text(label).font(.caption2).foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Chart

    private var chart: some View {
        Chart {
            ForEach(log.hr, id: \.t) { s in
                LineMark(x: .value("Time", s.t), y: .value("BPM", s.bpm))
                    .foregroundStyle(.red)
                    .interpolationMethod(.catmullRom)
            }
            ForEach(log.moments) { m in
                if let bpm = m.bpm {
                    PointMark(x: .value("Time", m.t), y: .value("BPM", bpm))
                        .foregroundStyle(selected?.id == m.id ? Color.orange : Color.blue)
                        .symbolSize(selected?.id == m.id ? 220 : 90)
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { value in
                AxisGridLine()
                AxisValueLabel { if let t = value.as(Double.self) { Text(fmtClock(t)) } }
            }
        }
        .frame(height: 220)
    }

    // MARK: - Moment cards

    private func momentCard(_ m: WorkoutMoment) -> some View {
        Button {
            withAnimation(.easeInOut) { selected = (selected?.id == m.id) ? nil : m }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(fmtClock(m.t)).font(.caption.monospaced()).foregroundColor(.gray)
                    Spacer()
                    if let bpm = m.bpm {
                        Label("\(bpm)", systemImage: "heart.fill")
                            .font(.caption).foregroundColor(.red)
                    }
                }
                Text("“\(m.transcript)”").font(.body)
                Text(m.analysis).font(.callout).foregroundColor(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background((selected?.id == m.id ? Color.orange.opacity(0.15) : Color.gray.opacity(0.12)))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }

    private func placeholder(_ text: String) -> some View {
        Text(text).font(.footnote).foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Formatting

    private func fmtClock(_ t: TimeInterval) -> String {
        let s = max(0, Int(t)); return String(format: "%d:%02d", s / 60, s % 60)
    }
    private func fmtDuration(_ t: TimeInterval) -> String { "\(max(0, Int(t) / 60)) min" }
}

/// Browse and reopen past workouts.
struct WorkoutHistoryView: View {
    @StateObject private var store = WorkoutStore.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if store.logs.isEmpty {
                    Text("No workouts yet.").foregroundColor(.secondary)
                } else {
                    List(store.logs) { log in
                        NavigationLink {
                            WorkoutReviewView(log: log)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(log.start.formatted(date: .abbreviated, time: .shortened))
                                Text("\(Int(log.duration) / 60) min · \(log.moments.count) moments"
                                     + (log.peakBPM.map { " · peak \($0)" } ?? ""))
                                    .font(.caption).foregroundColor(.gray)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Workouts")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
