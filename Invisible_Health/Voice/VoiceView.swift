import SwiftUI
import AudioToolbox

/// The "Voice" tab — a hands-free, interruptible voice conversation with the
/// AI coach. Tap the orb to connect; the agent greets you and you just talk.
///
/// During a workout it switches to hands-free "Hey Coach" mode: the agent stays
/// asleep (ignoring gym noise) until the on-device wake word fires, then listens
/// for a turn. See WakeWordDetector / WakeWordConfig.
struct VoiceView: View {
    // Injected from ContentView (app root) so the call + workout PERSIST across
    // tab switches. Previously these were @StateObject owned here, so switching
    // tabs recreated VoiceView → a NEW call, orphaning the live LiveKit session
    // (voice kept playing while the UI reset to the disconnected orb — the
    // "app went to first page but voice kept talking" bug).
    @ObservedObject var call: VoiceCallManager
    @ObservedObject var workout: WorkoutSessionController
    /// Set by the Plan/Profile tabs: "discuss" / "start" / "onboard". Performed on
    /// appear, then cleared.
    @Binding var pendingVoiceAction: String?
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

    /// Today's 3 plan options pushed by the coach (#11), and the onboarding sheet.
    @State private var planDeck: [CoachPlan]?
    @State private var showOnboarding = false
    /// The chosen workout, shown on screen during the session (set by the coach).
    @State private var currentWorkoutLabel: String?

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
            // During a workout the orb is just a visual — Start/Stop Workout is
            // the single control, so tapping the orb can't disconnect mid-workout.
            .disabled(call.state == .connecting || workout.isActive)

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

            // MARK: - Controls (only for casual chat — hidden during a workout,
            // where Start/Stop Workout is the single control to avoid confusion).
            if call.state == .connected && !workout.isActive {
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
        .onAppear {
            wireWorkout()
            // First run → onboarding. Otherwise, schedule the daily pre-workout
            // nudge (#12) so it can reach you before you open the app.
            if UserProfile.saved == nil {
                showOnboarding = true
            } else {
                NotificationManager.shared.requestAuthorization()
                NotificationManager.shared.schedulePreWorkoutNudge()
            }
            performPendingAction()
        }
        .onChange(of: pendingVoiceAction) { _ in performPendingAction() }
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
        .fullScreenCover(item: Binding(
            get: { planDeck.map { PlanDeck(plans: $0) } },
            set: { planDeck = $0?.plans })) { deck in
            PlanCardsView(plans: deck.plans, onSelect: { plan in
                planDeck = nil
                selectPlan(plan)
            }, onClose: { planDeck = nil })
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingChoiceView(
                onVoice: {
                    showOnboarding = false
                    Task {
                        if call.state != .connected { await call.start() }
                        await call.sendLocalTime()
                        await call.sendStartOnboarding()   // coach interviews by voice
                    }
                    NotificationManager.shared.requestAuthorization()
                    NotificationManager.shared.schedulePreWorkoutNudge()
                },
                onTextSaved: { p in
                    showOnboarding = false
                    Task { await call.sendProfile(p.dictionary) }
                    NotificationManager.shared.requestAuthorization()
                    NotificationManager.shared.schedulePreWorkoutNudge()
                })
        }
    }

    /// Wrapper so an array can drive `.fullScreenCover(item:)`.
    private struct PlanDeck: Identifiable { let id = UUID(); let plans: [CoachPlan] }

    /// User tapped a plan card: start the workout running that plan.
    private func selectPlan(_ plan: CoachPlan) {
        Task {
            if !workout.isActive { await beginWorkout() }
            currentWorkoutLabel = plan.title
        }
    }

    /// Persist the profile the coach gathered via the voice interview.
    private func saveProfileFromCoach(_ d: [String: Any]) {
        var p = UserProfile.saved ?? UserProfile()
        if let v = d["goal"] as? String { p.goal = v }
        if let v = d["preferred"] as? String { p.preferred = v }
        if let v = d["level"] as? String { p.level = v }
        if let v = d["days_per_week"] as? Int { p.daysPerWeek = v }
        if let v = d["equipment"] as? String { p.equipment = v }
        if let v = d["injuries"] as? String { p.injuries = v }
        p.save()
    }

    /// Connect (if needed), refresh Whoop, start the workout. Voice-first: the
    /// coach then PROPOSES today's plans out loud (staying awake for the chat).
    /// Hands-free "Hey Coach" is armed later, when the coach calls go_handsfree.
    private func beginWorkout() async {
        if call.state != .connected { await call.start() }
        currentWorkoutLabel = nil
        let ow = OpenWearablesManager.shared
        ow.checkConnectionStatus { ow.performSync() }
        workout.startWorkout()                      // broadcasts Whoop ctx to the agent
        await call.sendLocalTime()                  // coach greets by time of day
        // Pass the already-decided plan (if any) so the coach coaches THAT rather
        // than re-proposing; if none, the coach proposes inline.
        await call.sendWorkoutStarted(plan: PlannedWorkout.today?.decided)
    }

    /// Perform an action queued by the Plan/Profile tabs (discuss / start / onboard).
    private func performPendingAction() {
        guard let action = pendingVoiceAction else { return }
        pendingVoiceAction = nil
        Task {
            if call.state != .connected { await call.start() }
            await call.sendLocalTime()
            switch action {
            case "discuss": await call.sendDiscussWorkout()
            case "start":   if !workout.isActive { await beginWorkout() }
            case "onboard": await call.sendStartOnboarding()
            default: break
            }
        }
    }

    /// Switch to hands-free "Hey Coach" for the rest of the workout — triggered by
    /// the coach (go_handsfree) once the opening plan conversation is done.
    private func armHandsfree() {
        guard workout.isActive, !wakeArmed else { return }
        wakeArmed = call.enableWakeWord { handleWake() }
        if wakeArmed {
            workout.wakeModeSink = { Task { await call.sendWakeMode(true) } }
            for ms in [0, 600, 1500, 3000] {
                Task {
                    try? await Task.sleep(nanoseconds: UInt64(ms) * 1_000_000)
                    await call.sendWakeMode(true)
                }
            }
        }
    }

    // MARK: - Workout HR panel

    private var workoutPanel: some View {
        VStack(spacing: 12) {
            if workout.isActive {
                // The chosen workout for today (set by the coach once decided).
                if let label = currentWorkoutLabel {
                    Label(label, systemImage: "figure.run")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(Color.blue.opacity(0.18))
                        .foregroundColor(.blue).clipShape(Capsule())
                }

                // Live workout clock (ticks every second while active).
                if let start = workout.startedAt {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let elapsed = max(0, Int(context.date.timeIntervalSince(start)))
                        Label(
                            String(format: "%d:%02d", elapsed / 60, elapsed % 60),
                            systemImage: "stopwatch"
                        )
                        .font(.title3.weight(.semibold).monospacedDigit())
                        .foregroundColor(.white)
                    }
                }

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

                // Live outdoor distance + pace (GPS) — only shows once moving.
                if workout.distanceMeters > 20 {
                    HStack(spacing: 14) {
                        Label(String(format: "%.2f km", workout.distanceMeters / 1000),
                              systemImage: "location.fill")
                        if let pace = workout.pace {
                            Label(pace, systemImage: "speedometer")
                        }
                    }
                    .font(.subheadline.weight(.medium).monospacedDigit())
                    .foregroundColor(.white.opacity(0.85))
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
                        await beginWorkout()
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
                HStack(spacing: 20) {
                    Button("Past workouts") { showHistory = true }
                    Button("Edit profile") { showOnboarding = true }
                }
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
        // Agent → app: today's 3 plan options → present the plan cards (#11).
        call.onPlans = { plans in planDeck = plans }
        // Agent → app: outdoor run → start GPS (triggers the permission prompt).
        call.onStartGPS = { workout.startLocation() }
        // Agent → app: opening chat done → switch to hands-free "Hey Coach".
        call.onHandsfree = { armHandsfree() }
        // Agent → app: profile saved via the voice interview → store + dismiss.
        call.onProfileSaved = { dict in
            saveProfileFromCoach(dict)
            showOnboarding = false
        }
        // Agent → app: the chosen workout label → show it + save it as today's plan.
        call.onWorkoutLabel = { label in
            currentWorkoutLabel = label
            PlannedWorkout.save(label)
        }
        // (Re)send the latest Whoop snapshot — controller calls this on start and
        // every few seconds, so it survives the agent joining the room late.
        workout.whoopContextSink = {
            Task { await call.sendWhoopContext(whoopSnapshot()) }
        }
        // Forward live GPS distance/pace to the coach during outdoor workouts (#9).
        workout.geoSink = { dist, pace in
            Task { await call.sendGeo(distanceMeters: dist, pace: pace) }
        }
        // Send the onboarding profile to the coach when connected (#11).
        if let profile = UserProfile.saved {
            Task { await call.sendProfile(profile.dictionary) }
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
