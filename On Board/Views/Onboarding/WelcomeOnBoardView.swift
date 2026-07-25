//
//  WelcomeOnBoardView.swift
//  On Board
//
//  One-time celebration + pledge shown the moment a user is admitted off the
//  waitlist (or instantly via a golden-ticket invite). The Host — the app
//  icon with a face — speaks in two beats with Animal Crossing-style
//  typewriter text, flapping between his open-notch idle face and the
//  closed-mouth speech frames while each line types out. "Continue" pushes
//  the pledge signature screen; signing dismisses the whole cover.
//
//  Asset geometry: HostIdle / HostHappy / HostSpeech / HostHappySpeech all
//  share the same canvas HEIGHT (4267pt) with differing widths, so frames
//  are sized by height — sizing by width made the face jump between frames.
//

import SwiftUI

/// Per-user welcome-celebration bookkeeping.
///
/// The welcome must fire the first time a user reaches `complete`, but NOT for a
/// returning, already-complete user signing in on a fresh device. The signal
/// that distinguishes them is "did THIS install ever see this user mid-onboarding
/// (incomplete / waitlisted)". `markSeenIncomplete` records that persistently, so
/// the celebration still fires on a cold launch after an admission that happened
/// while the app was closed — the common admin-admit → "You're On Board!" push
/// path — which an in-session-only flag would miss. `hasShown` then guards
/// against ever repeating it.
enum WelcomeCelebration {
    private static func key(for userID: UUID) -> String {
        "welcomeShown.\(userID.uuidString)"
    }
    private static func incompleteKey(for userID: UUID) -> String {
        "sawIncompleteOnboarding.\(userID.uuidString)"
    }

    static func hasShown(for userID: UUID) -> Bool {
        UserDefaults.standard.bool(forKey: key(for: userID))
    }

    static func markShown(for userID: UUID) {
        UserDefaults.standard.set(true, forKey: key(for: userID))
    }

    /// Whether this install has ever observed this user needing onboarding.
    static func wasSeenIncomplete(for userID: UUID) -> Bool {
        UserDefaults.standard.bool(forKey: incompleteKey(for: userID))
    }

    static func markSeenIncomplete(for userID: UUID) {
        UserDefaults.standard.set(true, forKey: incompleteKey(for: userID))
    }
}

struct WelcomeOnBoardView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    /// The Host's voice preference — shared with the global Settings picker.
    /// The in-cover mute button toggles this same key.
    @AppStorage("soundEffectsMode") private var soundMode: SoundEffectsMode = .unlessSilenced

    let boardName: String?

    private enum Phase {
        case hidden      // pre-entrance
        case greeting    // neutral Host, "Guess what?"
        case reveal      // happy Host, "You're in!"
    }

    @State private var phase: Phase = .hidden
    /// Talking-sprite frame: open-notch faces are idle, speech-tail variants
    /// are the closed-mouth frames flapped through while text types.
    @State private var mouthClosed = false
    /// Typewriter progress into the current phase's line.
    @State private var visibleCharacters = 0
    @State private var revealDone = false
    @State private var showPledge = false
    /// Tap-to-skip: jumps the typewriter to the finished reveal (game-style).
    @State private var skipRequested = false
    /// Fires the fireworks on the reveal. Off under Reduce Motion and disabled
    /// in UI tests (a running animation would stall XCUITest's idle wait).
    @State private var fireworksActive = false
    /// Whether the Host's voice plays in THIS welcome. Seeded from the global
    /// `soundEffectsMode` (muted up front if the device is silenced and the mode
    /// respects the silent switch), but the in-cover button toggles only this —
    /// it never writes back to the global setting. Pressing it to unmute forces
    /// the voice audible even when silenced (a per-playing override).
    @State private var voiceOn = false

    private var celebrationFXEnabled: Bool {
        !ProcessInfo.processInfo.arguments.contains("-disableCelebrationFX")
    }

    private var script: String {
        switch phase {
        case .hidden: ""
        case .greeting: "Guess what?"
        case .reveal: "You're in!\nWelcome On Board."
        }
    }

    private var hostImageName: String {
        switch phase {
        case .hidden, .greeting:
            return mouthClosed ? "HostSpeech" : "HostIdle"
        case .reveal:
            return mouthClosed ? "HostHappySpeech" : "HostHappy"
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()

                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Spacer()
                        muteButton
                    }

                    Spacer()

                    hostWithBubble
                        .frame(maxWidth: .infinity, alignment: .center)  // Host + bubble centered as a unit

                    Spacer()

                    // The campus line sits directly above the CTA (no card of its
                    // own) and the two rise into place together on the reveal.
                    VStack(spacing: 14) {
                        VStack(spacing: 6) {
                            if let boardName {
                                Label(boardName, systemImage: "building.columns.fill")
                                    .fontStyle(.subheadline)
                                    .fontWeight(.semibold)
                            }

                            Text("Your board is live. New week every Monday.")
                                .fontStyle(.footnote)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }

                        Button {
                            fireworksActive = false      // stop the show on the way out
                            showPledge = true
                        } label: {
                            LoadingButtonLabel("Continue", systemImage: "arrow.forward", isLoading: false)
                        }
                        .buttonStyle(.boardPrimary)
                        .tint(.primary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .opacity(revealDone ? 1 : 0)
                    .offset(y: revealDone ? 0 : 24)
                    .disabled(!revealDone)
                }
                .safeAreaPadding()
                .padding(.horizontal, 8)
                // Fireworks burst behind the message on the reveal.
                .fireworks(isActive: fireworksActive, placement: .behind)
            }
            // Tap anywhere (game-style) to skip the typewriter to the reveal.
            .contentShape(.rect)
            .onTapGesture { if !revealDone { skipRequested = true } }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showPledge) {
                PledgeSignatureView {
                    dismiss()
                }
            }
        }
        .task { await runSequence() }
        .onDisappear { HostVoice.shared.stop() }
    }

    /// Per-playing mute for the Host's voice. It flips ONLY this welcome's
    /// `voiceOn` — it never changes the global `soundEffectsMode` (that lives in
    /// Settings). Unmuting forces the voice audible even if the device is
    /// silenced: an override that lasts just for this playing.
    private var muteButton: some View {
        Button {
            voiceOn.toggle()
            if voiceOn { HostVoice.shared.prepare(playsWhenSilenced: true) }
        } label: {
            Image(systemName: voiceOn ? "speaker.wave.2.fill" : "speaker.slash.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 38, height: 38)
                .background {
                    GlassBackground(shape: Circle(), fallback: AnyShapeStyle(.thinMaterial))
                    Circle().stroke(Color.primary.opacity(0.08), lineWidth: 1)
                }
                .contentTransition(.symbolEffect(.replace))
        }
        .opacity(phase == .hidden ? 0 : 1)
        .accessibilityLabel(voiceOn ? "Mute the Host" : "Unmute the Host")
    }

    // MARK: - The Host

    private var hostWithBubble: some View {
        HStack(alignment: .center, spacing: 4) {
            Image(hostImageName)
                .resizable()
                .scaledToFit()
                .frame(height: 104)
                // Solid color-art sprites (black on white). Invert for dark mode
                // so he's white on black. He's opaque, so he naturally occludes
                // the fireworks behind him — no background patch needed.
                .colorInverted(scheme == .dark)
                .rotationEffect(.degrees(phase == .hidden ? -14 : 0))
                .background {
                    // Soft glow anchors The Host in space rather than leaving
                    // it floating in a flat void.
                    Circle()
                        .fill(Color.primary.opacity(0.12))
                        .frame(width: 180, height: 180)
                        .blur(radius: 48)
                        .opacity(phase == .hidden ? 0 : 1)
                }
                .accessibilityLabel("The Host")

            // The bubble sits BESIDE The Host now, its tail reaching left toward
            // his mouth. It grows out of him from the leading edge on entrance.
            speechBubble
                .opacity(phase == .hidden ? 0 : 1)
                .scaleEffect(phase == .hidden ? 0.4 : 1, anchor: .leading)
        }
        .scaleEffect(phase == .hidden ? 0.6 : 1)
        .opacity(phase == .hidden ? 0 : 1)
        .sensoryFeedback(trigger: phase) { _, newPhase in
            switch newPhase {
            case .greeting: .impact(weight: .light)
            case .reveal: .success
            case .hidden: nil
            }
        }
    }

    /// The Host's dialogue. Sized against the full line (via a hidden copy) so
    /// it doesn't jitter while the typewriter fills it in. The reusable
    /// `HostSpeechBubble` provides the glass balloon + centered tail.
    private var speechBubble: some View {
        HostSpeechBubble {
            ZStack(alignment: .topLeading) {
                Text(script).hidden()
                Text(String(script.prefix(visibleCharacters)))
            }
            .fontStyle(.title3)
            .fontWeight(.heavy)
            .multilineTextAlignment(.leading)
            // The bubble is a hard-sized graphic (`fixedSize` keeps it from
            // jittering as the typewriter fills). Bound its Dynamic Type growth
            // so it can't overflow the screen at accessibility sizes — the same
            // message is announced to VoiceOver and echoed by the info card,
            // both of which scale freely.
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            .fixedSize()
            // Expose the whole line to VoiceOver, not the mid-typewriter prefix
            // — otherwise assistive tech reads a changing fragment on every
            // character step. Each phase change re-announces (mirrors the two
            // spoken beats).
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(script.replacingOccurrences(of: "\n", with: " ")))
        }
    }

    // MARK: - Sequence

    private func runSequence() async {
        guard phase == .hidden else { return }

        // Seed this playing's voice from the global setting. The in-cover button
        // then toggles only this `voiceOn` (never the global setting), and
        // unmuting forces the voice audible even when the device is silenced.
        voiceOn = soundMode.isOn

        if reduceMotion {
            phase = .reveal
            visibleCharacters = script.count
            mouthClosed = false
            revealDone = true
            return
        }

        // Warm the voice engine so the first blip lands without setup latency.
        if voiceOn {
            HostVoice.shared.prepare(playsWhenSilenced: soundMode.playsWhenSilenced)
        }

        withAnimation(.spring(duration: 0.5, bounce: 0.35)) {
            phase = .greeting
        }
        await speak(script)

        // Let "Guess what?" linger long enough to register before the reveal.
        if !skipRequested {
            try? await Task.sleep(for: .milliseconds(1200))
        }
        guard !Task.isCancelled else { return }

        // Swap neutral → happy as a hard sprite flip, not a crossfade: animating
        // the phase change here cross-dissolved the two face frames (a brief
        // ghosted blend). The face pops; only the info card/CTA below animate.
        var flip = Transaction(); flip.disablesAnimations = true
        withTransaction(flip) {
            phase = .reveal
            visibleCharacters = 0
        }
        if celebrationFXEnabled { fireworksActive = true }   // celebrate as the line lands
        await speak(script)

        withAnimation(.spring(duration: 0.4, bounce: 0.2)) {
            revealDone = true
        }
    }

    /// Animal Crossing-style delivery: text types on character by character
    /// while the mouth flaps between the idle and speech frames, settling
    /// open (idle) when the line lands. Frame swaps and character steps are
    /// unanimated — sprite flips, not crossfades.
    private func speak(_ line: String) async {
        let chars = Array(line)
        for index in 1...max(line.count, 1) {
            guard !Task.isCancelled else { return }
            // Tap-to-skip: snap the whole line in and bail.
            if skipRequested {
                var t = Transaction(); t.disablesAnimations = true
                withTransaction(t) { visibleCharacters = chars.count; mouthClosed = false }
                return
            }
            var t = Transaction(); t.disablesAnimations = true
            withTransaction(t) {
                visibleCharacters = index
                // Flap every 2 characters — a quicker mouth than every 3, which
                // read as slightly sluggish next to the typing cadence.
                mouthClosed = (index / 2) % 2 == 1
            }
            let ch = index <= chars.count ? chars[index - 1] : " "
            // The Host's voice: an Animalese-style blip per letter, driven by the
            // text itself (see HostVoice). Letters sound; spaces/punctuation are
            // the pauses. The happy set + higher pitch land on the reveal beat.
            if voiceOn {
                HostVoice.shared.speak(ch, at: index - 1, in: line, bright: phase == .reveal)
            }
            // Natural cadence: a real beat after punctuation, a hair slower per
            // character than a flat machine-gun typewriter.
            try? await Task.sleep(for: .milliseconds(Self.pause(after: ch)))
        }
        var t = Transaction(); t.disablesAnimations = true
        withTransaction(t) { mouthClosed = false }
    }

    private static func pause(after ch: Character) -> Int {
        switch ch {
        case ".", "!", "?": return 300
        case ",", ";", ":": return 175
        case "\n":          return 240
        // ~62ms/letter matches the voice cadence tuned in the offline render.
        default:            return 62
        }
    }
}

extension View {
    /// Inverts colors only when `on` — used to flip the black-on-white Host art
    /// to white-on-black for dark mode. The Host sprites are solid color art
    /// (render intent "original"), so tinting won't work; this does.
    @ViewBuilder
    func colorInverted(_ on: Bool) -> some View {
        if on { colorInvert() } else { self }
    }
}

#Preview("Welcome") {
    WelcomeOnBoardView(boardName: "Georgetown")
}

#Preview("Welcome — no board name") {
    WelcomeOnBoardView(boardName: nil)
}
