//
//  SettingsHapticsPreview.swift
//  On Board
//
//  The animated board mockup + haptic-shake demo shown at the top of Settings.
//  Fully self-contained: reads its own @AppStorage keys (shared with the
//  Haptics/Card-rotation controls in SettingsView via the same UserDefaults
//  keys) and owns the shake trigger, so SettingsView just embeds this view
//  with no wiring.
//

import SwiftUI
import UIKit

struct SettingsHapticsPreview: View {
    @AppStorage("hapticsEnabled") private var hapticsEnabled: Bool = true
    @AppStorage("rotationIntensity") private var rotationIntensity: Double = 0.7
    @Environment(\.dynamicTypeSize) private var typeSize

    @State private var triggerShake = 0
    @State private var previewRotations: [Double] = (0..<4).map { _ in Double.random(in: -6...6) }

    private let previewWidth: CGFloat = 184
    private let previewHeight: CGFloat = 256
    private let columns = [
        GridItem(.flexible(), spacing: 0),
        GridItem(.flexible(), spacing: 0)
    ]

    var body: some View {
        HStack(alignment: .center) {
            Spacer()
            ZigZagMark()
                .opacity(hapticsEnabled ? 1 : 0)
            Spacer()
            boardPreview
                .keyframeAnimator(initialValue: CGFloat(0), trigger: triggerShake) { content, offset in
                    content.offset(x: offset)
                } keyframes: { _ in
                    LinearKeyframe(3,  duration: 0.05)
                    LinearKeyframe(-6, duration: 0.05)
                    LinearKeyframe(6,  duration: 0.05)
                    LinearKeyframe(-6, duration: 0.05)
                    LinearKeyframe(3,  duration: 0.05)
                    LinearKeyframe(0,  duration: 0.05)
                }

            Spacer()
            ZigZagMark()
                .opacity(hapticsEnabled ? 1 : 0)
            Spacer()
        }
        .animation(.smooth(duration: 0.2), value: rotationIntensity)
        .animation(.smooth(duration: 0.2), value: hapticsEnabled)
        .frame(maxWidth: .infinity)
        .mask { LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .bottom).padding(.top, -6) }
        .listRowBackground(Color.clear)
        .offset(y: 24)
        .onChange(of: rotationIntensity) { oldValue, newValue in
            if oldValue == 0 && newValue > 0 { previewRotations = (0..<4).map { _ in Double.random(in: -6...6) } }
        }
        .onChange(of: hapticsEnabled) { _, on in if on { shakeAndVibrate() } }
    }

    // MARK: - Board preview

    private var boardPreview: some View {
        UnevenRoundedRectangle(cornerRadii: .init(topLeading: 48, topTrailing: 48))
            .fill(.ultraThinMaterial)
            .overlay {
                UnevenRoundedRectangle(cornerRadii: .init(topLeading: 48, topTrailing: 48))
                    .stroke(.quaternary, lineWidth: 6)
            }
            .frame(width: previewWidth, height: previewHeight)
            .overlay(alignment: .top) {
                Text("\"camera\"")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 16)
            }
            .overlay(alignment: .bottom) {
                if typeSize.isAccessibilitySize {
                    VStack(spacing: 14) {
                        ForEach(0..<2, id: \.self) { index in
                            PreviewCard(
                                index: index,
                                rotation: 0,
                                width: previewWidth * 0.85,
                                height: previewHeight / 2.5,
                                triggerShake: triggerShake,
                                hapticsEnabled: hapticsEnabled,
                                isMasonry: false
                            )
                        }
                    }
                } else {
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(0..<4, id: \.self) { index in
                            PreviewCard(
                                index: index,
                                rotation: previewRotations[index] * rotationIntensity,
                                width: previewWidth / 2.8,
                                height: previewHeight / 2.5,
                                triggerShake: triggerShake,
                                hapticsEnabled: hapticsEnabled,
                                isMasonry: true
                            )
                        }
                    }
                }
            }
            .clipShape(UnevenRoundedRectangle(cornerRadii: .init(topLeading: 48, topTrailing: 48)))
            .overlay(alignment: .topTrailing) {
                if typeSize.isAccessibilitySize {
                    Image(systemName: "accessibility")
                        .fontStyle(.footnote)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color(uiColor: .systemBackground))
                        .padding(4)
                        .background(.primary, in: .circle)
                        .offset(x: 4, y: -4)
                }
            }
    }

    // MARK: - Haptics

    private func shakeAndVibrate() {
        triggerShake += 1
        guard hapticsEnabled else { return }
        let hard = UIImpactFeedbackGenerator(style: .rigid)
        let soft = UIImpactFeedbackGenerator(style: .light)
        hard.prepare()
        soft.prepare()
        hard.impactOccurred(intensity: 1.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) {
            soft.impactOccurred(intensity: 0.8)
        }
        previewRotations = (0..<4).map { _ in Double.random(in: -6...6) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            soft.impactOccurred(intensity: 0.5)
        }
    }
}

// MARK: - Zig-zag haptic indicator

private struct ZigZagMark: View {
    var body: some View {
        Canvas { ctx, size in
            let inset: CGFloat = 2.0
            let w = size.width - (inset * 2)
            let h = size.height - (inset * 2)

            var path = Path()
            path.move(to:    CGPoint(x: inset + w * 0.5, y: inset))
            path.addLine(to: CGPoint(x: inset + w,       y: inset + h * 0.2))
            path.addLine(to: CGPoint(x: inset,           y: inset + h * 0.4))
            path.addLine(to: CGPoint(x: inset + w,       y: inset + h * 0.6))
            path.addLine(to: CGPoint(x: inset,           y: inset + h * 0.8))
            path.addLine(to: CGPoint(x: inset + w * 0.5, y: inset + h))

            ctx.stroke(path, with: .foreground, style: .init(lineWidth: 3, lineCap: .round, lineJoin: .round))
        }
        .frame(width: 14, height: 44)
    }
}

// MARK: - Preview Card

private struct PreviewCard: View {
    let index: Int
    let rotation: Double
    let width: CGFloat
    let height: CGFloat
    let triggerShake: Int
    let hapticsEnabled: Bool
    let isMasonry: Bool

    private let colors: [Color] = [.orange, .mint, .pink, .cyan]

    var body: some View {
        let color = colors[index % colors.count]

        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(color.opacity(0.2))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(color.opacity(0.8), lineWidth: 2)
            }
            .frame(width: width, height: height)
            .rotationEffect(.degrees(rotation))
            .keyframeAnimator(initialValue: Double(0), trigger: triggerShake) { content, wobble in
                content.rotationEffect(.degrees(hapticsEnabled ? wobble : 0))
            } keyframes: { _ in
                // Add a small playful wobble to each card independently
                CubicKeyframe(index.isMultiple(of: 2) ? 6 : -6, duration: 0.1)
                CubicKeyframe(index.isMultiple(of: 2) ? -4 : 4, duration: 0.12)
                CubicKeyframe(index.isMultiple(of: 2) ? 2 : -2, duration: 0.12)
                CubicKeyframe(0, duration: 0.1)
            }
            // Fake masonry layout: right column pushed down
            .offset(
                x: isMasonry ? (index.isMultiple(of: 2) ? 4 : -4) : 0,
                y: isMasonry ? (index.isMultiple(of: 2) ? 0 : 48) : 0
            )
    }
}

#Preview {
    Form {
        SettingsHapticsPreview()
    }
}
