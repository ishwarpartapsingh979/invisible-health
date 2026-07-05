import SwiftUI
import AudioToolbox

/// The "Voice" tab — a hands-free, interruptible voice conversation with the
/// AI coach. Tap the orb to connect; the agent greets you and you just talk.
///
/// During a workout it switches to hands-free "Hey Coach" mode: the agent stays
/// asleep (ignoring gym noise) until the on-device wake word fires, then listens
/// for a turn. See WakeWordDetector / WakeWordConfig.
struct VoiceView: View {
    @StateObject private var call = VoiceCallManager()
    @StateObject private var workout = WorkoutSessionController()
    @State private var pulse = false

    /// True while "Hey Coach" is armed for this workout (configured + connected).
    @State private var wakeArmed = false
    /// True briefly after a wake word fires, while the coach is actively listening.
    @State private var coachAwake = false
    @State private var awakeResetTask: Task<Void, Never>?

    /// The just-finished workout to review (drives the review sheet); and the
    /// history browser toggle.
    @State private var reviewLog: WorkoutLog?
    @State private var showHistory = false

    /// Exercise deck pushed by the coach ("show me shoulder exercises") — drives
    /// the full-screen swipeable card overlay.
    private struct ExerciseDeck: Identifiable { let id = UUID(); let muscle: String; let items: [ExerciseItem] }
    @State private var exerciseDeck: ExerciseDeck?
    /// Pings the agent to stay awake while the exercise deck is open.
    @State private var keepAliveTimer: Timer?

    var body: some View {
        VStack(spacing: 28) {
            Text("VOICE")
                .font(.caption)
                .fontWeight(.semibold)
                .tracking(3)
                .foregroundColor(.gray)

            Spacer()

            // MARK: - Orb
            Button {
                let haptic = UIImpactFeedbackGenerator(style: .medium)
                haptic.impactOccurred()
                Task { await toggleCall() }
            } label: {
                ZStack {
                    if isLive {
                        Circle()
                            .fill(RadialGradient(
                                gradient: Gradient(colors: [.blue.opacity(0.5), .clear]),
                                center: .center, startRadius: 50, endRadius: 160))
                            .frame(width: 280, height: 280)
                            .scaleEffect(pulse ? 1.25 : 0.85)
                            .opacity(pulse ? 0.9 : 0.2)
                            .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: pulse)
                    }

                    Circle()
                        .fill(LinearGradient(
                            gradient: Gradient(colors: orbColors),
                            startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 150, height: 150)
                        .shadow(color: orbColors.first!.opacity(0.6), radius: 22, x: 0, y: 10)
                        .overlay(
                            Image(systemName: orbIcon)
                                .font(.system(size: 48))
                                .foregroundColor(.white)
                        )
                }
            }
            .buttonStyle(.plain)
            .disabled(call.state == .connecting)

            // MARK: - Status
            Text(statusText)
                .font(.headline)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            if case .failed(let msg) = call.state {
                Text(msg)
                    .font(.footnote)
                    .foregroundColor(.orange)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            workoutPanel

            Spacer()

            // MARK: - Controls (only while connected)
            if call.state == .connected {
                HStack(spacing: 24) {
                    controlButton(
                        icon: call.isMicEnabled ? "mic.fill" : "mic.slash.fill",
                        tint: call.isMicEnabled ? .white : .red
                    ) { Task { await call.toggleMic() } }

                    controlButton(icon: "phone.down.fill", tint: .red) {
                        Task { await call.stop() }
                    }
                }
            }

            if !VoiceCallManager.isAvailable {
                Text("LiveKit SDK not linked — add the package in Xcode to enable Voice.")
                    .font(.caption2)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
        .padding(.vertical, 20)
        .onChange(of: isLive) { live in pulse = live }
        .onChange(of: exerciseDeck != nil) { deckOpen in
            // While the deck is open the user is browsing (silent) — ping the
            // coach to stay awake so it doesn't time out mid-browse.
            keepAliveTimer?.invalidate()
            if deckOpen {
                keepAliveTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
                    Task { await call.sendKeepAlive() }
                }
            } else {
                keepAliveTimer = nil
            }
        }
        .onAppear { wireWorkout() }
        .sheet(item: $reviewLog) { log in
            NavigationStack {
                WorkoutReviewView(log: log)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { reviewLog = nil }
                        }
                    }
            }
        }
        .sheet(isPresented: $showHistory) { WorkoutHistoryView() }
        .fullScreenCover(item: $exerciseDeck) { deck in
            ExerciseCardsView(muscle: deck.muscle, items: deck.items) {
                exerciseDeck = nil
            }
        }
    }

    // MARK: - Workout HR panel

    private var workoutPanel: some View {
        VStack(spacing: 12) {
            if workout.isActive {
                HStack(spacing: 10) {
                    Image(systemName: "heart.fill").foregroundColor(.red)
                    if let bpm = workout.currentBPM {
                        Text("\(bpm)")
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .monospacedDigit()
                        Text("BPM").font(.caption).foregroundColor(.gray)
                    } else {
                        Text(hrStatusText).font(.subheadline).foregroundColor(.gray)
                    }
                }
            }

            // Hands-free status while a workout is running with the wake word armed.
            if workout.isActive && wakeArmed {
                HStack(spacing: 8) {
                    Image(systemName: coachAwake ? "waveform" : "mic.badge.plus")
                        .foregroundColor(coachAwake ? .blue : .gray)
                    Text(coachAwake ? "Listening…" : "Say \u{201C}Hey Coach\u{201D}")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(coachAwake ? .blue : .gray)
                }
                .animation(.easeInOut, value: coachAwake)
            }

            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                Task {
                    if workout.isActive {
                        workout.wakeModeSink = nil
                        workout.stopWorkout()
                        call.disableWakeWord()
                        await call.sendWakeMode(false)
                        awakeResetTask?.cancel()
                        wakeArmed = false
                        coachAwake = false
                        // Persist the workout and open its review (HR graph +
                        // spoken moments) right away.
                        if let log = workout.makeLog() {
                            WorkoutStore.shared.save(log)
                            reviewLog = log
                        }
                    } else {
                        if call.state != .connected { await call.start() }
                        // Refresh Whoop data for the coach. Must check the
                        // connection FIRST — performSync() no-ops unless
                        // isWhoopConnected is set, which doesn't happen if you
                        // open the Voice tab before the Whoop/Summary tab. The
                        // periodic 5s whoop re-send then delivers it to the agent
                        // once the fetches land.
                        let ow = OpenWearablesManager.shared
                        ow.checkConnectionStatus { ow.performSync() }
                        workout.startWorkout()                      // broadcasts Whoop ctx to the agent
                        // Arm hands-free "Hey Coach" if it's set up; otherwise the
                        // session stays in normal always-on listening.
                        wakeArmed = call.enableWakeWord { handleWake() }
                        if wakeArmed {
                            // Put the agent to sleep until "Hey Coach". A single
                            // send races the agent joining the room and gets
                            // lost, so: (1) re-send on the controller's 5s tick
                            // (survives join + reconnect), and (2) burst now so
                            // it lands within ~1s of the agent appearing.
                            // Entering wake mode is idempotent on the agent.
                            workout.wakeModeSink = { Task { await call.sendWakeMode(true) } }
                            for ms in [0, 600, 1500, 3000] {
                                Task {
                                    try? await Task.sleep(nanoseconds: UInt64(ms) * 1_000_000)
                                    await call.sendWakeMode(true)
                                }
                            }
                        }
                    }
                }
            } label: {
                Text(workout.isActive ? "Stop Workout" : "Start Workout")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(workout.isActive ? Color.red.opacity(0.18) : Color.green.opacity(0.18))
                    .foregroundColor(workout.isActive ? .red : .green)
                    .cornerRadius(14)
            }
            .disabled(!VoiceCallManager.isAvailable)

            if !workout.isActive {
                Button("Past workouts") { showHistory = true }
                    .font(.footnote)
                    .foregroundColor(.gray)
            }
        }
    }

    private var hrStatusText: String {
        switch workout.hrState {
        case .idle:         return "Starting…"
        case .scanning:     return "Searching for Whoop…"
        case .connecting:   return "Connecting…"
        case .streaming:    return "—"
        case .disconnected: return "Reconnecting…"
        case .unsupported:  return "Bluetooth is off"
        case .unauthorized: return "Allow Bluetooth in Settings"
        }
    }

    /// Called on the main thread when the on-device "Hey Coach" wake word fires.
    /// Confirms with a chime + haptic, then tells the agent to open its ears.
    private func handleWake() {
        AudioServicesPlaySystemSound(1113)                        // short chime (iOS API)
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred() // buzz
        Task { await call.sendWake() }
        coachAwake = true
        // Reflect the agent's ~8s awake window in the UI (plus a little grace).
        awakeResetTask?.cancel()
        awakeResetTask = Task {
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            if !Task.isCancelled { coachAwake = false }
        }
    }

    /// Coach started/stopped listening (from the agent). On sleep, play a
    /// distinct descending tone + light haptic so the user knows it stopped.
    private func handleCoachState(_ state: String) {
        switch state {
        case "asleep":
            coachAwake = false
            awakeResetTask?.cancel()
            AudioServicesPlaySystemSound(1114)   // lower "stop" tone (wake uses 1113)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case "awake":
            coachAwake = true
        default:
            break
        }
    }

    private func wireWorkout() {
        // Forward each HR sample to the agent over the LiveKit data channel.
        workout.heartRateSink = { sample in
            Task { await call.sendHeartRate(sample) }
        }
        // Agent → app: a logged moment (transcript + breathing analysis + HR).
        call.onMoment = { transcript, analysis, bpm in
            workout.recordMoment(transcript: transcript, analysis: analysis, bpm: bpm)
        }
        // Agent → app: "show me <muscle> exercises" → present the card deck.
        call.onExercises = { muscle, items in
            exerciseDeck = ExerciseDeck(muscle: muscle, items: items)
        }
        // Agent → app: coach started/stopped listening. Play a cue on sleep so
        // the user knows it stopped, and keep the UI in sync.
        call.onCoachState = { state in handleCoachState(state) }
        // (Re)send the latest Whoop snapshot — controller calls this on start and
        // every few seconds, so it survives the agent joining the room late.
        workout.whoopContextSink = {
            Task { await call.sendWhoopContext(whoopSnapshot()) }
        }
        #if DEBUG
        // Headless Simulator pipeline test: launch with SIMCTL_CHILD_AUTO_WORKOUT=1
        // to auto-connect + start a (simulated) workout with no taps.
        if ProcessInfo.processInfo.environment["AUTO_WORKOUT"] == "1", !workout.isActive {
            Task {
                if call.state != .connected { await call.start() }
                workout.startWorkout()
            }
        }
        #endif
    }

    /// Latest Whoop snapshot (cached from Open Wearables) to seed the agent at
    /// workout start. Only includes fields we actually have.
    private func whoopSnapshot() -> [String: Any] {
        let ow = OpenWearablesManager.shared
        var s: [String: Any] = [:]
        if let r = ow.whoopRecovery {
            if let v = r.recoveryScore { s["recovery_score"] = v }
            if let v = r.avgHrvSdnnMs { s["hrv_ms"] = v }
            if let v = r.restingHeartRateBpm { s["resting_hr"] = v }
            if let v = r.avgSpo2Percent { s["spo2"] = v }
            s["recovery_level"] = r.recoveryLevel
        }
        if let sl = ow.whoopSleep {
            s["sleep_hours"] = sl.timeAsleepHours
            if let v = sl.efficiencyPercent { s["sleep_efficiency"] = v }
            if let v = sl.sleepPerformancePercentage { s["sleep_performance"] = v }
            if let v = sl.avgRespiratoryRate { s["respiratory_rate"] = v }
            if let v = sl.interruptionsCount { s["sleep_disturbances"] = v }
        }
        if let st = ow.whoopStrain {
            if let v = st.dayStrain { s["day_strain"] = v }
            if let v = st.averageHeartRate { s["day_avg_hr"] = v }
            if let v = st.maxHeartRate { s["day_max_hr"] = v }
            if let v = st.kilojoules { s["kilojoules"] = v }
            if let v = st.cardiovascularLoad { s["cardio_load"] = v }
            if let v = st.muscularLoad { s["muscular_load"] = v }
        }
        // Discrete activities from the events/workouts endpoint (running, walking,
        // etc.) — the real source now that OW's workout sync is fixed. (The strain
        // summary above does not carry per-workout sessions.)
        if !ow.whoopWorkouts.isEmpty {
            s["workouts"] = ow.whoopWorkouts.prefix(8).map { w -> [String: Any] in
                var d: [String: Any] = [:]
                if let v = w.type { d["sport"] = v }
                if let v = w.startTime { d["start"] = v }
                if let v = activityWhen(w.startTime) { d["when"] = v }
                if let v = w.durationMinutes { d["duration_min"] = v }
                if let v = w.avgHeartRateBpm { d["avg_hr"] = v }
                if let v = w.maxHeartRateBpm { d["max_hr"] = v }
                if let v = w.caloriesKcal { d["kcal"] = v }
                if let v = w.distanceMeters { d["distance_m"] = v }
                return d
            }
        }
        return s
    }

    /// Relative day for an activity ("today"/"yesterday"/"3 days ago"/"Sat Jun 27"),
    /// computed in the device's timezone so the coach states the correct day.
    private func activityWhen(_ iso: String?) -> String? {
        guard let iso else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = f.date(from: iso) ?? {
            f.formatOptions = [.withInternetDateTime]; return f.date(from: iso)
        }()
        guard let date else { return nil }
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "today" }
        if cal.isDateInYesterday(date) { return "yesterday" }
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: date),
                                      to: cal.startOfDay(for: Date())).day ?? 0
        if days >= 2 && days <= 6 { return "\(days) days ago" }
        let df = DateFormatter(); df.dateFormat = "EEE MMM d"
        return df.string(from: date)
    }

    // MARK: - Derived UI state

    private var isLive: Bool {
        call.state == .connected || call.state == .connecting
    }

    private var statusText: String {
        switch call.state {
        case .idle:        return "Tap to talk"
        case .connecting:  return "Connecting…"
        case .connected:   return "Listening — just speak"
        case .failed:      return "Tap to try again"
        }
    }

    private var orbColors: [Color] {
        switch call.state {
        case .connected:  return [.blue, .purple]
        case .connecting: return [.gray, .blue]
        case .failed:     return [.orange, .red]
        case .idle:       return [.indigo, .blue]
        }
    }

    private var orbIcon: String {
        switch call.state {
        case .connected:  return "waveform"
        case .connecting: return "ellipsis"
        default:          return "mic.fill"
        }
    }

    private func toggleCall() async {
        switch call.state {
        case .connected, .connecting: await call.stop()
        default:                      await call.start()
        }
    }

    private func controlButton(icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle()
                .fill(Color.white.opacity(0.1))
                .frame(width: 64, height: 64)
                .overlay(Image(systemName: icon).font(.system(size: 24)).foregroundColor(tint))
        }
    }
}
