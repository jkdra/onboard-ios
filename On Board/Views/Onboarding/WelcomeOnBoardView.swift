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

/// Per-user "has seen the welcome" flag. The welcome fires only on an
/// in-session transition from needs-onboarding → complete (so returning users
/// signing in on a new device never see it); this flag additionally guards
/// re-triggers within a session lifecycle.
enum WelcomeCelebration {
    private static func key(for userID: UUID) -> String {
        "welcomeShown.\(userID.uuidString)"
    }

    static func hasShown(for userID: UUID) -> Bool {
        UserDefaults.standard.bool(forKey: key(for: userID))
    }

    static func markShown(for userID: UUID) {
        UserDefaults.standard.set(true, forKey: key(for: userID))
    }
}

struct WelcomeOnBoardView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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

                VStack(spacing: 0) {
                    Spacer()

                    hostWithBubble

                    if revealDone {
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
                        .padding(.horizontal, 22)
                        .padding(.vertical, 14)
                        .background {
                            // Liquid-glass info card — the app's Aero-modern material.
                            GlassBackground(
                                shape: RoundedRectangle(cornerRadius: 20, style: .continuous),
                                fallback: AnyShapeStyle(.thinMaterial)
                            )
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                        }
                        .padding(.top, 30)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }

                    Spacer()

                    Button {
                        showPledge = true
                    } label: {
                        LoadingButtonLabel("Continue", systemImage: "arrow.forward", isLoading: false)
                    }
                    .buttonStyle(.boardPrimary)
                    .tint(.primary)
                    .opacity(revealDone ? 1 : 0)
                    .disabled(!revealDone)
                }
                .safeAreaPadding()
                .padding(.horizontal, 8)
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showPledge) {
                PledgeSignatureView {
                    dismiss()
                }
            }
        }
        .task { await runSequence() }
    }

    // MARK: - The Host

    private var hostWithBubble: some View {
        VStack(spacing: 0) {
            Image(hostImageName)
                .resizable()
                .scaledToFit()
                .frame(height: 116)
                .foregroundStyle(.primary)
                .rotationEffect(.degrees(phase == .hidden ? -14 : 0))
                .background {
                    // Soft glow anchors The Host in space rather than leaving
                    // it floating in a flat void.
                    Circle()
                        .fill(Color.primary.opacity(0.12))
                        .frame(width: 190, height: 190)
                        .blur(radius: 48)
                        .opacity(phase == .hidden ? 0 : 1)
                }
                .accessibilityLabel("The Host")

            speechBubble
                .opacity(phase == .hidden ? 0 : 1)
                .scaleEffect(phase == .hidden ? 0.4 : 1, anchor: .top)
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

    /// The bubble hangs UNDER The Host, its tail reaching up toward his
    /// mouth (right side of the glyph). Sized against the full line so it
    /// doesn't jitter while the typewriter fills it in.
    private var speechBubble: some View {
        ZStack(alignment: .topLeading) {
            Text(script).hidden()
            Text(String(script.prefix(visibleCharacters)))
        }
        .fontStyle(.title3)
        .fontWeight(.heavy)
        .multilineTextAlignment(.leading)
        // The bubble is a hard-sized graphic (`fixedSize` keeps it from
        // jittering as the typewriter fills). Bound its Dynamic Type growth so
        // it can't overflow the screen at accessibility sizes — the same
        // message is announced to VoiceOver and echoed by the info card, both
        // of which scale freely.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .fixedSize()
        .padding(.horizontal, 22)
        .padding(.top, 16 + SpeechBubbleShape.tailHeight)
        .padding(.bottom, 16)
        .background {
            // Clean, solid "game dialogue" bubble: an elevated surface lifted
            // by a soft shadow, with a hairline edge for definition in light
            // mode — no heavy comic outline (that read as clip-art). The Host
            // mascot carries the character; the bubble stays quiet and native.
            SpeechBubbleShape(tailOffsetX: 52)
                .fill(Color(.secondarySystemBackground))
                .shadow(color: .black.opacity(0.28), radius: 20, x: 0, y: 12)
            SpeechBubbleShape(tailOffsetX: 52)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
        // Expose the whole line to VoiceOver, not the mid-typewriter prefix —
        // otherwise assistive tech reads a changing fragment on every character
        // step. Each phase change re-announces (mirrors the two spoken beats).
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(script.replacingOccurrences(of: "\n", with: " ")))
    }

    // MARK: - Sequence

    private func runSequence() async {
        guard phase == .hidden else { return }

        if reduceMotion {
            phase = .reveal
            visibleCharacters = script.count
            mouthClosed = false
            revealDone = true
            return
        }

        withAnimation(.spring(duration: 0.5, bounce: 0.35)) {
            phase = .greeting
        }
        await speak(script)

        try? await Task.sleep(for: .milliseconds(450))
        guard !Task.isCancelled else { return }

        withAnimation(.spring(duration: 0.4, bounce: 0.25)) {
            phase = .reveal
            visibleCharacters = 0
        }
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
        for index in 1...max(line.count, 1) {
            guard !Task.isCancelled else { return }
            var t = Transaction(); t.disablesAnimations = true
            withTransaction(t) {
                visibleCharacters = index
                mouthClosed = (index / 3) % 2 == 1
            }
            try? await Task.sleep(for: .milliseconds(28))
        }
        var t = Transaction(); t.disablesAnimations = true
        withTransaction(t) { mouthClosed = false }
    }
}

/// Rounded-rect speech bubble with a curved tail on its top edge, drawn as
/// one continuous outline so the stroke has no seam where the tail meets the
/// body.
/// Rounded-rect bubble with a smooth, tapered tail on its top edge — one
/// continuous outline so a stroke has no seam where the tail meets the body.
/// The tail curves out of the top edge and narrows to a soft, rounded tip
/// (like a modern chat tail), not the old convex nub.
nonisolated struct SpeechBubbleShape: Shape {
    static let tailHeight: CGFloat = 20

    var cornerRadius: CGFloat = 22
    var tailWidth: CGFloat = 28
    /// Tail tip x, relative to the bubble's horizontal center — positive
    /// pushes it toward The Host's mouth side.
    var tailOffsetX: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let tailHeight = Self.tailHeight
        let body = CGRect(
            x: rect.minX, y: rect.minY + tailHeight,
            width: rect.width, height: rect.height - tailHeight
        )
        let r = min(cornerRadius, min(body.width, body.height) / 2)

        // Keep the tail's base on the straight part of the top edge.
        let half = tailWidth / 2
        let tipX = min(max(rect.midX + tailOffsetX, body.minX + r + half + 2),
                       body.maxX - r - half - 2)
        let baseLeft = CGPoint(x: tipX - half, y: body.minY)
        let baseRight = CGPoint(x: tipX + half, y: body.minY)
        // Tip leans slightly toward the mouth side and rounds over softly.
        let tip = CGPoint(x: tipX + tailWidth * 0.16, y: rect.minY)

        var p = Path()
        p.move(to: CGPoint(x: body.minX + r, y: body.minY))
        p.addLine(to: baseLeft)
        // Left flank sweeps up and tapers into the rounded tip.
        p.addCurve(
            to: tip,
            control1: CGPoint(x: baseLeft.x + tailWidth * 0.34, y: body.minY - tailHeight * 0.34),
            control2: CGPoint(x: tip.x - tailWidth * 0.24, y: tip.y + tailHeight * 0.30)
        )
        // Right flank comes back down to the top edge.
        p.addCurve(
            to: baseRight,
            control1: CGPoint(x: tip.x + tailWidth * 0.22, y: tip.y + tailHeight * 0.26),
            control2: CGPoint(x: baseRight.x + tailWidth * 0.04, y: body.minY - tailHeight * 0.40)
        )
        p.addLine(to: CGPoint(x: body.maxX - r, y: body.minY))
        p.addArc(center: CGPoint(x: body.maxX - r, y: body.minY + r), radius: r,
                 startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: body.maxX, y: body.maxY - r))
        p.addArc(center: CGPoint(x: body.maxX - r, y: body.maxY - r), radius: r,
                 startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: body.minX + r, y: body.maxY))
        p.addArc(center: CGPoint(x: body.minX + r, y: body.maxY - r), radius: r,
                 startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        p.addLine(to: CGPoint(x: body.minX, y: body.minY + r))
        p.addArc(center: CGPoint(x: body.minX + r, y: body.minY + r), radius: r,
                 startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        p.closeSubpath()
        return p
    }
}

#Preview("Welcome") {
    WelcomeOnBoardView(boardName: "Georgetown")
}

#Preview("Welcome — no board name") {
    WelcomeOnBoardView(boardName: nil)
}
