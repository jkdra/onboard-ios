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
    let counts: [Reaction: Int]
    let tone: PostTone
    @Binding var selected: Reaction?
    var isInteractive: Bool = true
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @AppStorage("hapticsEnabled") private var hapticsEnabled: Bool = true

    private let outerRadius: CGFloat = 20
    private let innerRadius: CGFloat = 4
    private let interButtonSpacing: CGFloat = 4

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: interButtonSpacing) {
                    ForEach(Array(Reaction.allCases.enumerated()), id: \.element) { index, reaction in
                        accessibleButton(for: reaction, position: position(at: index))
                    }
                }
            } else {
                HStack(spacing: interButtonSpacing) {
                    ForEach(Array(Reaction.allCases.enumerated()), id: \.element) { index, reaction in
                        button(for: reaction, position: position(at: index))
                    }
                }
            }
        }
        .sensoryFeedback(trigger: selected) { _, _ in
            hapticsEnabled && isInteractive ? .impact(weight: .light) : nil
        }
        .allowsHitTesting(isInteractive)
        .opacity(isInteractive ? 1 : 0.85)
    }
    
    private func accessibleButton(for reaction: Reaction, position: Position) -> some View {
        let count = displayCount(for: reaction)
        let isSelected = selected == reaction
        return Button {
            guard isInteractive else { return }
            withAnimation(.smooth(duration: 0.2)) {
                selected = isSelected ? nil : reaction
            }
        } label: {
            HStack(spacing: 6) {
                Text(reaction.emoji)
                    .fontStyle(.caption)
                Text(reaction.label)
                    .fontStyle(.caption)
                Divider()
                Text(count.abbreviated)
                    .fontStyle(.caption)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .contentTransition(.numericText(value: Double(count)))
                    .animation(.snappy(duration: 0.35), value: count)
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                UnevenRoundedRectangle(
                    cornerRadii: position.accessibleCorners(outer: outerRadius, inner: innerRadius),
                    style: .continuous
                )
                .fill(
                    isSelected
                    ? tone.color.opacity(scheme == .dark ? 0.55 : 0.40)
                    : Color(.systemBackground).opacity(0.45)
                )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(reaction.label), \(count)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func button(for reaction: Reaction, position: Position) -> some View {
        let count = displayCount(for: reaction)
        let isSelected = selected == reaction
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
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                UnevenRoundedRectangle(
                    cornerRadii: position.corners(outer: outerRadius, inner: innerRadius),
                    style: .continuous
                )
                .fill(
                    isSelected
                    ? tone.color.opacity(scheme == .dark ? 0.55 : 0.40)
                    : Color(.systemBackground).opacity(0.45)
                )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(reaction.label), \(count)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func position(at index: Int) -> Position {
        if index == 0 { return .first }
        if index == Reaction.allCases.count - 1 { return .last }
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
        
        func accessibleCorners(outer: CGFloat, inner: CGFloat) -> RectangleCornerRadii {
            switch self {
                case .first:
                    RectangleCornerRadii(
                        topLeading: outer,
                        bottomLeading: inner,
                        bottomTrailing: inner,
                        topTrailing: outer
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
                        bottomLeading: outer,
                        bottomTrailing: outer,
                        topTrailing: inner
                    )
            }
        }
    }
}
