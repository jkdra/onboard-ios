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
        VStack(spacing: 0) {
            if edge == .bottom { Spacer(minLength: 0) }
            bar
                .frame(height: active.barHeight)
                .blur(radius: active.blurRadius)
            if edge == .top { Spacer(minLength: 0) }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onAppear {
            // Draw the fill on from the leading edge, then start the periodic shimmer.
            withAnimation(.smooth(duration: 0.8)) { fill = target }
            startShimmer()
        }
        .onChange(of: step) { _, _ in
            withAnimation(.smooth(duration: growDuration)) { fill = target }
            startShimmer()
        }
        .onChange(of: shimmerDuration) { _, _ in startShimmer() }
    }

    private var bar: some View {
        ZStack {
            // Base horizontal fill — flat color out to the animated fill, feathers to clear.
            LinearGradient(
                stops: [
                    .init(color: tintColor.opacity(active.baseOpacity), location: 0),
                    .init(color: tintColor.opacity(active.baseOpacity), location: fill),
                    .init(color: .clear, location: min(fill + 0.06, 1)),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )

            // Shimmer — bright band swept via animated UnitPoints, masked to the fill region.
            LinearGradient(
                colors: [.clear, shimmerColor.opacity(active.shimmerOpacity), .clear],
                startPoint: UnitPoint(x: shimmerCenter - shimmerW, y: 0.5),
                endPoint:   UnitPoint(x: shimmerCenter + shimmerW, y: 0.5)
            )
            .blendMode(.plusLighter)
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .white, location: 0),
                        .init(color: .white, location: fill),
                        .init(color: .clear, location: min(fill + 0.05, 1)),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
        }
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

// MARK: - Interactive preview harness

private struct OnboardingProgressBackgroundLab: View {
    @State private var step: Double = 2
    @State private var schemeIsDark = false

    // Independent per-scheme presets the sliders edit.
    @State private var light = OnboardingProgressBackground.Intensity.lightDefault
    @State private var dark  = OnboardingProgressBackground.Intensity.darkDefault

    @State private var shimmerW: CGFloat = 0.14
    @State private var shimmerDuration: Double = 3.4

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
                shimmerW: shimmerW,
                shimmerDuration: shimmerDuration
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
        VStack(alignment: .leading, spacing: 12) {
            Picker("Scheme", selection: $schemeIsDark) {
                Text("Light").tag(false)
                Text("Dark").tag(true)
            }
            .pickerStyle(.segmented)

            slider("Step", value: $step, range: 1...4, step: 1, format: "%.0f")
            slider("Base opacity", value: dbl(editing.baseOpacity), range: 0...1, format: "%.2f")
            slider("Shimmer opacity", value: dbl(editing.shimmerOpacity), range: 0...1, format: "%.2f")
            slider("Bar height", value: cg(editing.barHeight), range: 2...60, format: "%.0f")
            slider("Blur radius", value: cg(editing.blurRadius), range: 0...100, format: "%.0f")
            slider("Shimmer width", value: cg($shimmerW), range: 0.02...0.4, format: "%.2f")
            slider("Shimmer duration", value: $shimmerDuration, range: 0.5...8, format: "%.1fs")
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
