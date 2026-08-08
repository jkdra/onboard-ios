import SwiftUI

// DEV-ONLY tuning lab for the Host rig — reachable exclusively via the
// `-dev.hostLab` launch argument (RootView short-circuits to it before any
// auth/onboarding logic). Never wired to a shipping surface.
//
// Two jobs:
//   1. Tune the computed shadow (weight, axis) and component anatomy
//      (eye/article position + scale) against the drawn reference until
//      they're indistinguishable at the default 8° pose.
//   2. Audition character animations — pose-driven, so the world-fixed
//      shadow adaptation is exercised by every preset.

struct HostLabView: View {
    @State private var bodyState: HostBodyState = .idle
    @State private var eye: HostEye = .neutral
    @State private var article: HostArticle? = nil

    @State private var poseDegrees: Double = -8
    @State private var weight: Double = 0.075
    @State private var axisDX: Double = 0.045
    @State private var axisDY: Double = 0.085
    @State private var halo: Double = 0.05

    @State private var anatomy = HostAnatomy()
    @State private var animation: LabAnimation = .none
    @State private var darkStage = false

    enum LabAnimation: String, CaseIterable {
        case none = "Still"
        case nervous = "Nervous"
        case angry = "Angry"
        case bob = "Bob"

        /// Pose offset in degrees at time t. Nervous = broad worried sway;
        /// angry = tight rapid buzz; bob = slow idle breathing tilt.
        func poseOffset(at t: TimeInterval) -> Double {
            switch self {
            case .none: 0
            case .nervous: sin(t * 2 * .pi * 5) * 3.0
            case .angry: sin(t * 2 * .pi * 14) * 1.4
            case .bob: sin(t * 2 * .pi * 0.6) * 2.0
            }
        }

        /// Presets bring their own article so the emotion reads instantly.
        var impliedArticle: HostArticle? {
            switch self {
            case .nervous: .sweat
            case .angry: .anger
            case .none, .bob: nil
            }
        }

        var impliedEye: HostEye? {
            switch self {
            case .nervous: .bugged
            case .angry: .angry
            case .none, .bob: nil
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            stage
            Divider()
            controls
        }
        .background(Color(.systemGroupedBackground))
        .onAppear(perform: applyLaunchOverrides)
    }

    /// Headless capture support: `-dev.hostLab.body speech`,
    /// `-dev.hostLab.eye bugged`, `-dev.hostLab.article sweat`,
    /// `-dev.hostLab.anim nervous`, `-dev.hostLab.dark YES` — taps can't be
    /// synthesized on this machine's tooling, so every lab state must be
    /// reachable from launch arguments.
    private func applyLaunchOverrides() {
        let defaults = UserDefaults.standard
        if let raw = defaults.string(forKey: "dev.hostLab.body"),
           let state = HostBodyState(rawValue: raw) { bodyState = state }
        if let raw = defaults.string(forKey: "dev.hostLab.eye"),
           let state = HostEye(rawValue: raw) { eye = state }
        if let raw = defaults.string(forKey: "dev.hostLab.article"),
           let state = HostArticle(rawValue: raw) { article = state }
        if let raw = defaults.string(forKey: "dev.hostLab.anim"),
           let preset = LabAnimation.allCases.first(where: { $0.rawValue.lowercased() == raw.lowercased() }) {
            animation = preset
            if let impliedArticle = preset.impliedArticle { article = impliedArticle }
            if let impliedEye = preset.impliedEye { eye = impliedEye }
        }
        if defaults.bool(forKey: "dev.hostLab.dark") { darkStage = true }
    }

    private var stage: some View {
        ZStack {
            // Explicit stage colors — an adaptive color here turns the
            // light stage black in dark mode and hides the black contour.
            (darkStage ? Color.black : Color.white)
            TimelineView(.animation(minimumInterval: nil, paused: animation == .none)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                HostFigure(
                    body_: bodyState,
                    eye: eye,
                    article: article,
                    pose: .degrees(poseDegrees + animation.poseOffset(at: t)),
                    weight: weight,
                    axis: CGVector(dx: axisDX, dy: axisDY),
                    halo: halo,
                    anatomy: anatomy,
                    lineColor: darkStage ? .white : .black,
                    bodyColor: darkStage ? .black : .white
                )
                .frame(width: 230)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 380)
        .onTapGesture { darkStage.toggle() }
    }

    private var controls: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Picker("Body", selection: $bodyState) {
                    ForEach(HostBodyState.allCases, id: \.self) { Text($0.rawValue.capitalized) }
                }
                .pickerStyle(.segmented)

                Picker("Eye", selection: $eye) {
                    ForEach(HostEye.allCases, id: \.self) { Text($0.rawValue.capitalized) }
                }
                .pickerStyle(.menu)

                Picker("Article", selection: $article) {
                    Text("None").tag(HostArticle?.none)
                    ForEach(HostArticle.allCases, id: \.self) { Text($0.rawValue.capitalized).tag(HostArticle?.some($0)) }
                }
                .pickerStyle(.segmented)

                Picker("Animate", selection: $animation) {
                    ForEach(LabAnimation.allCases, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .onChange(of: animation) { _, preset in
                    if let impliedArticle = preset.impliedArticle { article = impliedArticle }
                    if let impliedEye = preset.impliedEye { eye = impliedEye }
                }

                labSlider("Pose °", $poseDegrees, -30...30)
                labSlider("Weight", $weight, 0.02...0.16)
                labSlider("Axis X", $axisDX, -0.15...0.15)
                labSlider("Axis Y", $axisDY, -0.15...0.15)
                labSlider("Halo", $halo, 0.01...0.12)

                Text("Anatomy").font(.headline).padding(.top, 4)
                labSlider("Eye X", $anatomy.eyeCenter.x, 0...1)
                labSlider("Eye Y", $anatomy.eyeCenter.y, 0...1)
                labSlider("Eye size", $anatomy.eyeScale, 0.1...0.5)
                if article == .sweat {
                    labSlider("Sweat X", $anatomy.sweatCenter.x, -0.3...1)
                    labSlider("Sweat Y", $anatomy.sweatCenter.y, -0.3...1)
                    labSlider("Sweat size", $anatomy.sweatScale, 0.1...0.5)
                }
                if article == .anger {
                    labSlider("Anger X", $anatomy.angerCenter.x, 0...1.3)
                    labSlider("Anger Y", $anatomy.angerCenter.y, -0.3...1)
                    labSlider("Anger size", $anatomy.angerScale, 0.1...0.5)
                }

                // Current values, screenshot-readable — this is how tuned
                // numbers make it back into HostAnatomy/HostFigure defaults.
                Text(currentValues)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            .padding()
        }
    }

    private func labSlider(_ label: String, _ value: Binding<Double>, _ range: ClosedRange<Double>) -> some View {
        HStack {
            Text(label).font(.caption).frame(width: 70, alignment: .leading)
            Slider(value: value, in: range)
            Text(String(format: "%.3f", value.wrappedValue))
                .font(.caption.monospaced())
                .frame(width: 48, alignment: .trailing)
        }
    }

    private func labSlider(_ label: String, _ value: Binding<CGFloat>, _ range: ClosedRange<Double>) -> some View {
        labSlider(label, Binding(get: { Double(value.wrappedValue) }, set: { value.wrappedValue = CGFloat($0) }), range)
    }

    private var currentValues: String {
        String(
            format: "pose %.1f  weight %.3f  axis (%.3f, %.3f)  halo %.3f\neye (%.3f, %.3f) ×%.3f  sweat (%.3f, %.3f) ×%.3f  anger (%.3f, %.3f) ×%.3f",
            poseDegrees, weight, axisDX, axisDY, halo,
            anatomy.eyeCenter.x, anatomy.eyeCenter.y, anatomy.eyeScale,
            anatomy.sweatCenter.x, anatomy.sweatCenter.y, anatomy.sweatScale,
            anatomy.angerCenter.x, anatomy.angerCenter.y, anatomy.angerScale
        )
    }
}

#Preview {
    HostLabView()
}
