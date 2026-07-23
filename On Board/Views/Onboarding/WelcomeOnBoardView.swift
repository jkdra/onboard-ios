//
//  WelcomeOnBoardView.swift
//  On Board
//
//  One-time celebration shown the moment a user is admitted off the waitlist
//  (or instantly via a golden-ticket invite). The Host — the app icon with a
//  face — greets them in two beats: he arrives mid-sentence with a neutral
//  dot eye ("Guess what?"), then his eye flips to the happy squint as the
//  bubble lands the news. The expression change is the celebration; nothing
//  else on the screen competes with it.
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

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                hostWithBubble

                if phase == .reveal {
                    VStack(spacing: 16) {
                        if let boardName {
                            Label(boardName, systemImage: "building.columns.fill")
                                .fontStyle(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Capsule(style: .continuous).fill(.thinMaterial))
                        }

                        Text("Your board is live. New week every Monday.")
                            .fontStyle(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 36)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Label("Step on board", systemImage: "arrow.forward")
                }
                .buttonStyle(.boardPrimary)
                .tint(.primary)
                .opacity(phase == .reveal ? 1 : 0)
                .disabled(phase != .reveal)
            }
            .safeAreaPadding()
            .padding(.horizontal, 8)
        }
        .task { await runSequence() }
    }

    // MARK: - The Host

    /// The speech-variant assets shape the mouth notch as a bubble tail
    /// pointing right, about 40% down the glyph — the bubble hangs off it.
    private var hostWithBubble: some View {
        HStack(alignment: .top, spacing: -6) {
            Image(phase == .reveal ? "HostHappySpeech" : "HostSpeech")
                .resizable()
                .scaledToFit()
                .frame(width: 150)
                .foregroundStyle(.primary)
                .rotationEffect(.degrees(phase == .hidden ? -14 : 0))
                .accessibilityLabel("The Host")

            speechBubble
                .offset(y: 34)
                .opacity(phase == .hidden ? 0 : 1)
                .scaleEffect(phase == .hidden ? 0.4 : 1, anchor: .bottomLeading)
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

    /// Brand card bubble — same language as the verification email: thick
    /// primary border with a hard offset shadow, no blur.
    private var speechBubble: some View {
        Group {
            if phase == .reveal {
                VStack(alignment: .leading, spacing: 2) {
                    Text("You're in!")
                    Text("Welcome On Board.")
                }
            } else {
                Text("Guess what?")
            }
        }
        .fontStyle(.title3)
        .fontWeight(.heavy)
        .fixedSize()
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.primary)
                    .offset(x: 5, y: 5)
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.systemBackground))
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.primary, lineWidth: 3)
            }
        }
    }

    // MARK: - Sequence

    private func runSequence() async {
        guard phase == .hidden else { return }

        if reduceMotion {
            phase = .reveal
            return
        }

        withAnimation(.spring(duration: 0.55, bounce: 0.35)) {
            phase = .greeting
        }

        try? await Task.sleep(for: .milliseconds(1400))
        guard !Task.isCancelled else { return }

        withAnimation(.spring(duration: 0.5, bounce: 0.3)) {
            phase = .reveal
        }
    }
}

#Preview("Welcome") {
    WelcomeOnBoardView(boardName: "Georgetown")
}

#Preview("Welcome — no board name") {
    WelcomeOnBoardView(boardName: nil)
}
