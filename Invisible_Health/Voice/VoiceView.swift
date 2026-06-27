import SwiftUI

/// The "Voice" tab — a hands-free, interruptible voice conversation with the
/// AI coach. Tap the orb to connect; the agent greets you and you just talk.
struct VoiceView: View {
    @StateObject private var call = VoiceCallManager()
    @StateObject private var workout = WorkoutSessionController()
    @State private var pulse = false

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
        .onAppear { wireWorkout() }
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

            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                Task {
                    if workout.isActive {
                        workout.stopWorkout()
                    } else {
                        if call.state != .connected { await call.start() }
                        workout.startWorkout()
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

    private func wireWorkout() {
        // Forward each HR sample to the agent over the LiveKit data channel.
        workout.heartRateSink = { sample in
            Task { await call.sendHeartRate(sample) }
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
