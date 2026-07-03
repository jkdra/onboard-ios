//
//  OnboardingProgressBackground.swift
//  On Board
//

import SwiftUI

struct OnboardingProgressBackground: View {
    let step: Int
    var totalSteps: Int = 4

    // Intensity preset — differs by color scheme (light must be cranked up to read
    // against a bright background). Overridable so the preview lab can drive it live.
    var light: Intensity = .lightDefault
    var dark: Intensity  = .darkDefault

    // Which screen edge the glow emits from.
    var edge: VerticalEdge = .top

    // Shared identity / motion — consistent across schemes.
    var tintColor: Color = .blue
    var shimmerColor: Color = .teal
    var shimmerW: CGFloat = 0.18       // half-width of the shimmer band, unit coords
    var shimmerDuration: Double = 5.8  // seconds for one sweep
    var growDuration: Double = 0.7     // seconds to grow the fill when the step advances

    // Optional polka-dot mask: cut the (blurred) glow into a field of soft dots while
    // keeping the same fill + shimmer underneath.
    var useDotMask: Bool = false
    var dotRadius: CGFloat = 3
    var dotSpacing: CGFloat = 11
    // Height of the dot field as a fraction of the container, so the blurred halo has room
    // to fade out inside the frame instead of being clipped at the band's edge.
    var dotFieldFraction: CGFloat = 0.28

    @State private var shimmerPhase: CGFloat = 0
    @State private var fill: CGFloat = 0       // animated fill fraction; eased toward `target`
    @Environment(\.colorScheme) private var scheme

    /// Per-scheme intensity knobs.
    struct Intensity: Equatable {
        var baseOpacity: Double
        var shimmerOpacity: Double
        var barHeight: CGFloat
        var blurRadius: CGFloat

        static let lightDefault = Intensity(baseOpacity: 1.00, shimmerOpacity: 0.72, barHeight: 55, blurRadius: 38)
        static let darkDefault  = Intensity(baseOpacity: 1.00, shimmerOpacity: 0.70, barHeight: 48, blurRadius: 53)
    }

    private var active: Intensity { scheme == .dark ? dark : light }

    /// Target fill for the current step. Step 0 is 0, so the glow draws on from the
    /// leading edge as the user advances.
    private var target: CGFloat {
        min(1, CGFloat(step) / CGFloat(totalSteps))
    }

    private var shimmerCenter: CGFloat {
        (-shimmerW) + (fill + shimmerW * 2) * shimmerPhase
    }

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                if edge == .bottom { Spacer(minLength: 0) }
                maskedBar(containerHeight: proxy.size.height)
                if edge == .top { Spacer(minLength: 0) }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onAppear {
            // Draw the fill on from the leading edge, then start the periodic shimmer.
            withAnimation(.smooth(duration: 0.8)) { fill = target }
            startShimmer()
        }
        .onChange(of: step) { _, _ in
            // Only grow the fill. Do NOT restart the shimmer here — restarting reset its
            // phase and re-applied the 0.3s delay, which read as a visible "pause, then
            // jump" on every step. shimmerCenter reads the live `fill`, so the sweep range
            // extends smoothly as the fill grows while the band keeps moving continuously.
            withAnimation(.smooth(duration: growDuration)) { fill = target }
        }
        .onChange(of: shimmerDuration) { _, _ in startShimmer() }
    }

    // The blurred glow, optionally cut into crisp polka-dots. The dot mask is applied
    // AFTER the blur so the dots stay sharp while each one samples the blurred glow's
    // brightness at its position — dots sit bright near the screen edge and fade as they
    // move inward, following the glow's falloff.
    //
    // In dot mode the glow is placed in a tall field (≥ dotFieldFraction of the screen),
    // anchored to the emitting edge, so the blurred halo fades out *within* the frame — the
    // dot mask no longer clips it against the band's hard edge (the "cut-off").
    @ViewBuilder
    private func maskedBar(containerHeight: CGFloat) -> some View {
        let glow = bar
            .frame(height: active.barHeight)
            .blur(radius: active.blurRadius)
        if useDotMask {
            let fieldHeight = max(active.barHeight, containerHeight * dotFieldFraction)
            glow
                .frame(height: fieldHeight, alignment: edge == .bottom ? .bottom : .top)
                .mask(PolkaDotMask(radius: dotRadius, spacing: dotSpacing))
        } else {
            glow
        }
    }

    private var bar: some View {
        ZStack {
            baseFill
            shimmer
        }
    }

    // Base horizontal fill — flat color out to the animated fill, feathers to clear.
    // At fill 0 (sign-in / step 0) the whole band is clear, so nothing shows until the
    // fill grows in from the leading edge — otherwise the 0.06 feather leaves a sliver.
    private var baseFill: some View {
        let op = fill <= 0 ? 0 : active.baseOpacity
        return LinearGradient(
            stops: [
                .init(color: tintColor.opacity(op), location: 0),
                .init(color: tintColor.opacity(op), location: fill),
                .init(color: .clear, location: min(fill + 0.06, 1)),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    // Shimmer — bright band swept via animated UnitPoints, masked to the fill region.
    private var shimmer: some View {
        LinearGradient(
            colors: [.clear, shimmerColor.opacity(active.shimmerOpacity), .clear],
            startPoint: UnitPoint(x: shimmerCenter - shimmerW, y: 0.5),
            endPoint: UnitPoint(x: shimmerCenter + shimmerW, y: 0.5)
        )
        .blendMode(.plusLighter)
        .mask(shimmerMask)
    }

    private var shimmerMask: some View {
        let w: Double = fill <= 0 ? 0 : 1
        return LinearGradient(
            stops: [
                .init(color: .white.opacity(w), location: 0),
                .init(color: .white.opacity(w), location: fill),
                .init(color: .clear, location: min(fill + 0.05, 1)),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private func startShimmer() {
        shimmerPhase = 0
        withAnimation(
            .easeInOut(duration: shimmerDuration)
                .repeatForever(autoreverses: false)
                .delay(0.3)
        ) {
            shimmerPhase = 1
        }
    }
}

// MARK: - Polka-dot mask

/// A field of dots used as a mask so the gradient shows through as polka-dots.
/// Drawn in a single `Canvas` pass — no per-dot SwiftUI views, so it's cheap to render.
private struct PolkaDotMask: View {
    var radius: CGFloat
    var spacing: CGFloat

    var body: some View {
        Canvas { context, size in
            var y = spacing / 2
            var row = 0
            while y <= size.height + radius {
                // Offset alternate rows so the dots stagger instead of forming a hard grid.
                let rowOffset: CGFloat = row.isMultiple(of: 2) ? 0 : spacing / 2
                var x = spacing / 2 + rowOffset
                while x <= size.width + radius {
                    let dot = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
                    context.fill(Path(ellipseIn: dot), with: .color(.white))
                    x += spacing
                }
                y += spacing
                row += 1
            }
        }
    }
}

// MARK: - Interactive preview harness

private struct OnboardingProgressBackgroundLab: View {
    @State private var step: Double = 2
    @State private var schemeIsDark = false

    // Independent per-scheme presets the sliders edit.
    @State private var light = OnboardingProgressBackground.Intensity.lightDefault
    @State private var dark  = OnboardingProgressBackground.Intensity.darkDefault

    @State private var shimmerW: CGFloat = 0.14
    @State private var shimmerDuration: Double = 3.4

    @State private var useDotMask = false
    @State private var dotRadius: CGFloat = 3
    @State private var dotSpacing: CGFloat = 11
    @State private var dotFieldFraction: CGFloat = 0.28
    @State private var tintIsPrimary = false

    private var editing: Binding<OnboardingProgressBackground.Intensity> {
        schemeIsDark ? $dark : $light
    }

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            OnboardingProgressBackground(
                step: Int(step.rounded()),
                light: light,
                dark: dark,
                tintColor: tintIsPrimary ? .primary : .blue,
                shimmerW: shimmerW,
                shimmerDuration: shimmerDuration,
                useDotMask: useDotMask,
                dotRadius: dotRadius,
                dotSpacing: dotSpacing,
                dotFieldFraction: dotFieldFraction
            )

            VStack {
                Spacer()
                controls
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
                    .padding()
            }
        }
        .preferredColorScheme(schemeIsDark ? .dark : .light)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Pinned: the two you reach for most.
            Picker("Scheme", selection: $schemeIsDark) {
                Text("Light").tag(false)
                Text("Dark").tag(true)
            }
            .pickerStyle(.segmented)

            slider("Step", value: $step, range: 1...4, step: 1, format: "%.0f")

            // Everything else folds away and scrolls, so it never eats the whole screen.
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    section("Intensity") {
                        slider("Base opacity", value: dbl(editing.baseOpacity), range: 0...1, format: "%.2f")
                        slider("Shimmer opacity", value: dbl(editing.shimmerOpacity), range: 0...1, format: "%.2f")
                        slider("Bar height", value: cg(editing.barHeight), range: 2...60, format: "%.0f")
                        slider("Blur radius", value: cg(editing.blurRadius), range: 0...100, format: "%.0f")
                    }

                    section("Shimmer") {
                        slider("Shimmer width", value: cg($shimmerW), range: 0.02...0.4, format: "%.2f")
                        slider("Shimmer duration", value: $shimmerDuration, range: 0.5...8, format: "%.1fs")
                    }

                    section("Dots & tint") {
                        Toggle("Use .primary tint", isOn: $tintIsPrimary)
                            .font(.caption.weight(.semibold))
                        Toggle("Polka-dot mask", isOn: $useDotMask)
                            .font(.caption.weight(.semibold))
                        if useDotMask {
                            slider("Dot radius", value: cg($dotRadius), range: 1...8, format: "%.1f")
                            slider("Dot spacing", value: cg($dotSpacing), range: 6...30, format: "%.0f")
                            slider("Dot field height", value: cg($dotFieldFraction), range: 0.1...0.6, format: "%.2f")
                        }
                    }
                }
            }
            .frame(maxHeight: 300)
        }
    }

    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) { content() }
                .padding(.top, 4)
        } label: {
            Text(title).font(.caption.weight(.bold))
        }
    }

    // MARK: Binding bridges

    private func dbl(_ b: Binding<Double>) -> Binding<Double> { b }
    private func cg(_ b: Binding<CGFloat>) -> Binding<Double> {
        Binding(get: { Double(b.wrappedValue) }, set: { b.wrappedValue = CGFloat($0) })
    }

    private func slider(
        _ label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double = 0.01,
        format: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(.caption).fontWeight(.semibold)
                Spacer()
                Text(String(format: format, value.wrappedValue))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: step)
        }
    }
}

#Preview("Progress background — lab") {
    OnboardingProgressBackgroundLab()
}
