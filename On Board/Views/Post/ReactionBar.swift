//
//  ReactionBar.swift
//  On Board
//
//  Segmented reaction selector. Buttons sit as one tight strip — outer ends
//  use a large radius, the seams between buttons use a small one so the row
//  reads as a single pill cluster.
//

import SwiftUI

struct ReactionBar: View {
    @Environment(\.enabledReactions) private var enabledReactions
    @Environment(\.glassEffectsEnabled) private var glassEffectsEnabled
    let counts: [Reaction: Int]
    let tone: PostTone
    @Binding var selected: Reaction?
    var isInteractive: Bool = true
    var isRecord: Bool = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @AppStorage("hapticsEnabled") private var hapticsEnabled: Bool = true

    private let outerRadius: CGFloat = 32
    private let innerRadius: CGFloat = 4
    private let interButtonSpacing: CGFloat = 4

    var body: some View {
        reactionStrip
            .sensoryFeedback(trigger: selected) { _, _ in
                hapticsEnabled && isInteractive && !isRecord ? .impact(weight: .light) : nil
            }
            .allowsHitTesting(isInteractive && !isRecord)
            .opacity(isRecord ? 1 : (isInteractive ? 1 : 0.85))
    }

    @ViewBuilder
    private var reactionStrip: some View {
        reactionLayout
    }

    @ViewBuilder
    private var reactionLayout: some View {
        if isRecord {
            recordLayout
        } else if typeSize.isAccessibilitySize {
            accessibleMenu
        } else {
            HStack(spacing: interButtonSpacing) {
                ForEach(Array(enabledReactions.enumerated()), id: \.element) { index, reaction in
                    button(for: reaction, position: position(at: index))
                }
            }
        }
    }

    @ViewBuilder
    private var recordLayout: some View {
        let shape = UnevenRoundedRectangle(
            cornerRadii: RectangleCornerRadii(
                topLeading: outerRadius, bottomLeading: outerRadius,
                bottomTrailing: outerRadius, topTrailing: outerRadius
            ),
            style: .continuous
        )
        HStack(spacing: 0) {
            ForEach(Array(enabledReactions.enumerated()), id: \.element) { index, reaction in
                let count = displayCount(for: reaction)
                HStack(spacing: 5) {
                    Text(reaction.emoji)
                        .fontStyle(.caption)
                    Text(count.abbreviated)
                        .fontStyle(.caption)
                        .opacity(0.75)
                }
                .foregroundStyle(.primary)
                // Archived (read-only) week: mark the viewer's own reaction with
                // a subtle underline under just that reaction's emoji+count. An
                // overlay, so it never shifts the row's spacing/alignment.
                .overlay(alignment: .bottom) {
                    if selected == reaction {
                        Capsule()
                            .fill(Color.primary.opacity(0.5))
                            .frame(height: 2)
                            .offset(y: 5)
                    }
                }
                .frame(maxWidth: .infinity)

                if index < enabledReactions.count - 1 {
                    Circle().foregroundStyle(.quaternary)
                        .frame(width: 4, height: 4)
                }
            }
        }
        .padding()
        .background {
            if #available(iOS 26.0, *), glassEffectsEnabled {
                Color.clear.glassEffect(.regular, in: shape)
            } else {
                shape.fill(Color(.systemBackground).opacity(0.45))
            }
        }
    }

    private var accessibleMenu: some View {
        let currentReaction = selected
        let shape = UnevenRoundedRectangle(
            cornerRadii: RectangleCornerRadii(
                topLeading: outerRadius, bottomLeading: outerRadius,
                bottomTrailing: outerRadius, topTrailing: outerRadius
            ),
            style: .continuous
        )
        return Menu {
            ForEach(enabledReactions, id: \.self) { reaction in
                let count = displayCount(for: reaction)
                Button {
                    guard isInteractive else { return }
                    withAnimation(.smooth(duration: 0.2)) {
                        selected = currentReaction == reaction ? nil : reaction
                    }
                } label: {
                    Label(
                        "\(reaction.label)  \(count.abbreviated)",
                        systemImage: currentReaction == reaction ? "checkmark" : ""
                    )
                }
            }
            if currentReaction != nil {
                Divider()
                Button(role: .destructive) {
                    withAnimation(.smooth(duration: 0.2)) { selected = nil }
                } label: {
                    Label("Remove reaction", systemImage: "xmark")
                }
            }
        } label: {
            HStack(spacing: 6) {
                if let current = currentReaction {
                    Text(current.emoji)
                    Text(current.label)
                        .fontStyle(.caption)
                } else {
                    Image(systemName: "heart.fill")
                    Text("React")
                        .fontStyle(.caption)
                }
            }
            .foregroundStyle(currentReaction != nil ? tone.legibleForeground : .primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .contentShape(shape)
            .background(reactionBackground(shape: shape, isSelected: currentReaction != nil))
        }
        .disabled(!isInteractive)
        .accessibilityLabel(currentReaction.map { "\($0.label) selected" } ?? "React")
    }

    private func button(for reaction: Reaction, position: Position) -> some View {
        let count = displayCount(for: reaction)
        let isSelected = selected == reaction
        let shape = UnevenRoundedRectangle(
            cornerRadii: position.corners(outer: outerRadius, inner: innerRadius),
            style: .continuous
        )
        return Button {
            guard isInteractive else { return }
            withAnimation(.smooth(duration: 0.2)) {
                selected = isSelected ? nil : reaction
            }
        } label: {
            HStack(spacing: 6) {
                Text(reaction.emoji)
                    .fontStyle(.caption)
                Text(count.abbreviated)
                    .fontStyle(.caption)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .contentTransition(.numericText(value: Double(count)))
                    .animation(.snappy(duration: 0.35), value: count)
            }
            .foregroundStyle(isSelected ? tone.legibleForeground : .primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical)
            .contentShape(shape)
            .background(reactionBackground(shape: shape, isSelected: isSelected))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(reaction.label), \(count)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    @ViewBuilder
    private func reactionBackground(shape: UnevenRoundedRectangle, isSelected: Bool) -> some View {
        if #available(iOS 26.0, *), glassEffectsEnabled {
            Color.clear.glassEffect(
                isSelected
                ? .regular.tint(tone.color).interactive()
                : .regular.interactive(),
                in: shape
            )
        } else {
            shape.fill(
                isSelected
                ? tone.color.opacity(scheme == .dark ? 0.55 : 0.40)
                : Color(.systemBackground).opacity(0.45)
            )
        }
    }

    private func position(at index: Int) -> Position {
        if index == 0 { return .first }
        if index == enabledReactions.count - 1 { return .last }
        return .middle
    }

    private func displayCount(for reaction: Reaction) -> Int {
        counts[reaction] ?? 0
    }

    private enum Position {
        case first, middle, last

        func corners(outer: CGFloat, inner: CGFloat) -> RectangleCornerRadii {
            switch self {
            case .first:
                RectangleCornerRadii(
                    topLeading: outer,
                    bottomLeading: outer,
                    bottomTrailing: inner,
                    topTrailing: inner
                )
            case .middle:
                RectangleCornerRadii(
                    topLeading: inner,
                    bottomLeading: inner,
                    bottomTrailing: inner,
                    topTrailing: inner
                )
            case .last:
                RectangleCornerRadii(
                    topLeading: inner,
                    bottomLeading: inner,
                    bottomTrailing: outer,
                    topTrailing: outer
                )
            }
        }
        
    }
}
