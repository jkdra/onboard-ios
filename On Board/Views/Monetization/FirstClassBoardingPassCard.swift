//
//  FirstClassBoardingPassCard.swift
//  On Board
//
//  The signature element of On Board First Class: a die-cut boarding-pass ticket.
//  Pure monochrome — the card is `Color.primary` on the app's paper, so it
//  inverts with light/dark automatically (ink card in light, paper card in dark),
//  the same trick `SettingsIconBadge` uses. Butler carries the "First Class"
//  wordmark; everything readable stays on the system `.fontStyle`.
//
//  Used two ways: as the tappable hero row in Settings (its own section above
//  Account), and as the header of `FirstClassView` (`isHero`), where it also
//  gets a Host peek and an ambient sheen — kept off the compact Settings row so
//  the row list stays quiet.
//

import SwiftUI

// MARK: - Ticket silhouette

/// A rounded rectangle pinched by two semicircle notches at `notch` (a fraction
/// of the width), carving a real tear-away stub. The notches are true die-cuts —
/// they reveal whatever is behind the ticket — so the perforation reads as paper,
/// not paint.
struct TicketShape: Shape {
    var notch: CGFloat = 0.68
    var notchRadius: CGFloat = 11
    var corner: CGFloat = 22

    nonisolated func path(in rect: CGRect) -> Path {
        let x = rect.minX + rect.width * notch
        let r = notchRadius
        let c = corner
        var p = Path()

        // Top edge: left corner → into the top notch → right corner.
        p.move(to: CGPoint(x: rect.minX + c, y: rect.minY))
        p.addLine(to: CGPoint(x: x - r, y: rect.minY))
        p.addArc(center: CGPoint(x: x, y: rect.minY), radius: r,
                 startAngle: .degrees(180), endAngle: .degrees(0), clockwise: true)
        p.addLine(to: CGPoint(x: rect.maxX - c, y: rect.minY))
        p.addArc(center: CGPoint(x: rect.maxX - c, y: rect.minY + c), radius: c,
                 startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)

        // Right edge → bottom-right corner.
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - c))
        p.addArc(center: CGPoint(x: rect.maxX - c, y: rect.maxY - c), radius: c,
                 startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)

        // Bottom edge: right → into the bottom notch → left corner.
        p.addLine(to: CGPoint(x: x + r, y: rect.maxY))
        p.addArc(center: CGPoint(x: x, y: rect.maxY), radius: r,
                 startAngle: .degrees(0), endAngle: .degrees(180), clockwise: true)
        p.addLine(to: CGPoint(x: rect.minX + c, y: rect.maxY))
        p.addArc(center: CGPoint(x: rect.minX + c, y: rect.maxY - c), radius: c,
                 startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)

        // Left edge → back to start.
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + c))
        p.addArc(center: CGPoint(x: rect.minX + c, y: rect.minY + c), radius: c,
                 startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        p.closeSubpath()
        return p
    }
}

// MARK: - Boarding-pass card

struct FirstClassBoardingPassCard: View {
    enum Mode: Equatable {
        case promo                      // not subscribed — the sell
        case member(renewal: String?)   // subscribed — the membership pass
    }

    var mode: Mode = .promo
    /// Larger hero proportions when used as the screen header; compact in Settings.
    var isHero: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @State private var didAppear = false
    @State private var hostBob = false
    @State private var shimmerPhase: CGFloat = -0.4

    private var ink: Color { .primary }
    private var onInk: Color { Color(.systemBackground) }

    private var notchFraction: CGFloat { isHero ? 0.74 : 0.7 }
    /// Ambient (Host bob, sheen sweep) motion is skipped under XCUITest — a
    /// permanently non-idle app stalls the runner's tap/wait synthesis — and
    /// under Reduce Motion.
    private var ambientMotionEnabled: Bool { isHero && !reduceMotion && !RuntimeEnvironment.isRunningTests }

    var body: some View {
        ZStack(alignment: .top) {
            if isHero {
                hostPeek
            }

            ticketBody
                // Entrance: a light spring overshoot rather than a flat fade —
                // hero only. The compact Settings row already gets its own
                // entrance from the List's row-insertion animation; giving it
                // this too meant it could still be mid-scale/offset when a
                // tap landed right after appearing (also a plain unnecessary
                // flourish on a small list row — the hero is where this earns
                // its keep). Skipped entirely for Reduce Motion.
                .scaleEffect(!isHero || didAppear || reduceMotion ? 1 : 0.88, anchor: .top)
                .opacity(!isHero || didAppear || reduceMotion ? 1 : 0)
                .offset(y: !isHero || didAppear || reduceMotion ? 0 : -14)
        }
        .onAppear {
            guard isHero, !didAppear else { return }
            if reduceMotion {
                didAppear = true
            } else {
                withAnimation(.spring(response: 0.55, dampingFraction: 0.68)) { didAppear = true }
            }
            if ambientMotionEnabled {
                withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                    hostBob = true
                }
                withAnimation(.linear(duration: 3.2).repeatForever(autoreverses: false).delay(0.6)) {
                    shimmerPhase = 1.4
                }
            }
        }
    }

    private var ticketBody: some View {
        HStack(spacing: 0) {
            mainStub
                .frame(maxWidth: .infinity, alignment: .leading)
            perforation
            tearStub
                .frame(width: isHero ? 92 : 74)
        }
        .padding(.vertical, isHero ? 22 : 16)
        .background(
            TicketShape(notch: notchFraction, notchRadius: isHero ? 13 : 11)
                .fill(ink)
        )
        .overlay {
            if ambientMotionEnabled {
                TicketShape(notch: notchFraction, notchRadius: isHero ? 13 : 11)
                    .fill(sheenGradient)
                    .allowsHitTesting(false)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        // No explicit `.isButton` trait here: in Settings this view is the LABEL of a
        // real interactive `Button`, which already supplies the button trait itself —
        // adding it again here created two overlapping button-like accessibility nodes
        // at the same rect (mirrors the toolbar `Menu`'s "Automation type mismatch"
        // symptom) and made XCUITest's tap synthesis intermittently miss. As the
        // non-interactive hero in FirstClassView it correctly reads as plain content.
    }

    // MARK: Host peek

    /// The Host's mark rising up from behind the ticket's top edge — pure
    /// z-order, no masking: it's drawn BEHIND `ticketBody` in this ZStack, so
    /// the ticket's opaque fill naturally covers its lower portion, leaving
    /// only the top sliver "peeking" over the edge. A slow bob is its only
    /// motion, gated off under XCUITest/Reduce Motion via `ambientMotionEnabled`.
    ///
    /// `HostIdle` is fixed white-body / dark-eye art (`template-rendering-intent:
    /// original` — `.foregroundStyle` is a no-op on it). Two combined treatments:
    /// - **Dark mode:** `colorInverted` — the app's standard Host dark treatment
    ///   (`RootView`/`CountdownCard`/`WelcomeOnBoardView`), matching the intended
    ///   dark art (`LaunchHostDark` is a true RGB-invert of the light Host).
    /// - **Light mode:** `hostFloatShadow` — the natural white body plus a soft
    ///   shadow so it separates from the near-white page (a die-cut sticker
    ///   peeking over the pass). The shadow is a no-op in dark, where the
    ///   inverted white outline already reads on the dark page.
    private var hostPeek: some View {
        Image("HostIdle")
            .resizable()
            .scaledToFit()
            .frame(width: 46, height: 46)
            .colorInverted(scheme == .dark)
            .hostFloatShadow(scheme)
            .offset(y: (hostBob ? -36 : -32))
            .rotationEffect(.degrees(hostBob ? -4 : 4))
            .accessibilityHidden(true)
    }

    private var sheenGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: onInk.opacity(0), location: shimmerPhase - 0.18),
                .init(color: onInk.opacity(0.16), location: shimmerPhase),
                .init(color: onInk.opacity(0), location: shimmerPhase + 0.18),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: Left (main) section

    private var mainStub: some View {
        VStack(alignment: .leading, spacing: isHero ? 8 : 5) {
            Label {
                Text("ON BOARD")
                    .font(ButlerFont.medium(isHero ? 15 : 13))
                    .tracking(3)
            } icon: {
                Image(systemName: "airplane")
                    .font(.system(size: isHero ? 13 : 11, weight: .bold))
            }
            .foregroundStyle(onInk.opacity(0.65))

            Text("First Class")
                .font(ButlerFont.extraBold(isHero ? 46 : 32))
                .foregroundStyle(onInk)
                .fixedSize(horizontal: false, vertical: true)

            Text(subtitle)
                .fontStyle(.footnote)
                .foregroundStyle(onInk.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, isHero ? 24 : 18)
        .padding(.trailing, 14)
    }

    private var subtitle: String {
        switch mode {
        case .promo:
            "Skip the ads. Unlock the good stuff."
        case .member(let renewal):
            renewal.map { "You're all set · \($0.lowercased())" } ?? "You're all set."
        }
    }

    // MARK: Perforation

    private var perforation: some View {
        // A dashed rule between the two die-cut notches sells the tear line.
        Line()
            .stroke(style: StrokeStyle(lineWidth: 1.4, dash: [3, 4]))
            .foregroundStyle(onInk.opacity(0.35))
            .frame(width: 1.4)
            .padding(.vertical, isHero ? 18 : 12)
    }

    // MARK: Right (tear-away) stub

    private var tearStub: some View {
        VStack(spacing: isHero ? 6 : 4) {
            switch mode {
            case .promo:
                Text("SEAT")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(2)
                    .foregroundStyle(onInk.opacity(0.55))
                Text("1A")
                    .font(ButlerFont.medium(isHero ? 30 : 24))
                    .foregroundStyle(onInk)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(onInk.opacity(0.7))
            case .member:
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: isHero ? 30 : 24, weight: .semibold))
                    .foregroundStyle(onInk)
                Text("MEMBER")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(2)
                    .foregroundStyle(onInk.opacity(0.6))
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var accessibilityLabel: String {
        switch mode {
        case .promo:
            "On Board First Class. Skip the ads and unlock more. Subscribe."
        case .member(let renewal):
            renewal.map { "On Board First Class membership. \($0)." }
                ?? "On Board First Class membership."
        }
    }
}

/// A 1pt vertical line, used for the perforation stroke.
private struct Line: Shape {
    nonisolated func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return p
    }
}

extension View {
    /// Light-mode float for the Host art: a soft shadow that separates its white
    /// body from the near-white page without a filled backdrop. A no-op in dark,
    /// where the Host is colour-inverted to a white outline that already reads on
    /// the dark page. Shared by the ticket's Host peek and the celebration Host.
    func hostFloatShadow(_ scheme: ColorScheme) -> some View {
        shadow(color: .black.opacity(scheme == .dark ? 0.0 : 0.22), radius: 5, x: 0, y: 2)
    }
}

#Preview("Boarding pass") {
    VStack(spacing: 20) {
        FirstClassBoardingPassCard(mode: .promo)
        FirstClassBoardingPassCard(mode: .member(renewal: "Renews monthly"))
        FirstClassBoardingPassCard(mode: .promo, isHero: true)
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
