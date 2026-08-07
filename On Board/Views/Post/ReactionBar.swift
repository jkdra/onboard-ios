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
    @Environment(\.reactionOverflowEnabled) private var reactionOverflowEnabled
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

    /// How many reactions are permanent pills under the overflow layout. The
    /// split is positional, so `enabledReactions`' ORDER decides which two —
    /// reorder the config value to change them, don't special-case a case here.
    static let permanentCount = 2

    // MARK: - What the strip renders

    /// Which reactions get pills and which stay behind the "+".
    ///
    /// A pure function of its inputs, and `internal` rather than private, so
    /// the tests exercise THIS code instead of a copy of it — every interesting
    /// state here depends on other people's counts landing a certain way, which
    /// no amount of tapping around the simulator can stage.
    ///
    /// Two rules worth not breaking:
    ///
    /// * A reaction anyone has used is ALWAYS a pill. An earlier sketch gave
    ///   the viewer one slot showing whichever of laugh/hug *they* picked —
    ///   which meant choosing hug on a post with 12 laughs hid all 12, so a
    ///   private choice erased the board's loudest signal for an audience of
    ///   one, silently.
    /// * Order follows `enabled`, never count magnitude. Pills that reshuffle
    ///   as counts tick move the tap target out from under a finger already on
    ///   its way down, and destroy any muscle memory for where dislike sits.
    static func partition(
        enabled: [Reaction],
        counts: [Reaction: Int],
        selected: Reaction?,
        overflowEnabled: Bool
    ) -> (visible: [Reaction], hidden: [Reaction]) {
        guard overflowEnabled, enabled.count > permanentCount else { return (enabled, []) }
        // Selection counts as weight too, so a pill can't blink out during the
        // optimistic window before the count catches up.
        func hasWeight(_ reaction: Reaction) -> Bool {
            (counts[reaction] ?? 0) > 0 || selected == reaction
        }
        let visible = enabled.enumerated()
            .filter { $0.offset < permanentCount || hasWeight($0.element) }
            .map(\.element)
        let hidden = enabled.dropFirst(permanentCount).filter { !hasWeight($0) }
        return (visible, Array(hidden))
    }

    private var layout: (visible: [Reaction], hidden: [Reaction]) {
        Self.partition(
            enabled: enabledReactions,
            counts: counts,
            selected: selected,
            overflowEnabled: reactionOverflowEnabled
        )
    }

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
            let (reactions, hidden) = layout
            // +1 slot for the overflow menu when anything is still behind it,
            // so the end pill gets the outer radius rather than a seam.
            let slots = reactions.count + (hidden.isEmpty ? 0 : 1)
            HStack(spacing: interButtonSpacing) {
                ForEach(Array(reactions.enumerated()), id: \.element) { index, reaction in
                    button(for: reaction, position: position(at: index, of: slots))
                }
                if !hidden.isEmpty {
                    overflowMenu(hidden, position: position(at: slots - 1, of: slots))
                }
            }
        }
    }

    /// The "+" pill. A real `Menu`, not a long-press on another pill: a hidden
    /// gesture would be invisible to VoiceOver, and would have to win
    /// arbitration against `DoubleTapHeart` and the zoom transition's
    /// interactive pop on the same card.
    private func overflowMenu(_ hidden: [Reaction], position: Position) -> some View {
        let shape = UnevenRoundedRectangle(
            cornerRadii: position.corners(outer: outerRadius, inner: innerRadius),
            style: .continuous
        )
        return Menu {
            ForEach(hidden, id: \.self) { reaction in
                Button {
                    guard isInteractive else { return }
                    withAnimation(.smooth(duration: 0.2)) { selected = reaction }
                } label: {
                    // Emoji inline in the title: a menu row's `systemImage`
                    // slot takes SF Symbols, not emoji, and the empty-string
                    // trick used above is only there to reserve the checkmark.
                    Text("\(reaction.emoji)  \(reaction.label)")
                }
            }
        } label: {
            Image(systemName: "plus")
                .fontStyle(.caption)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical)
                .contentShape(shape)
                .background(reactionBackground(shape: shape, isSelected: false))
        }
        .disabled(!isInteractive)
        .accessibilityLabel("More reactions")
    }

    private var recordLayout: some View {
        let shape = UnevenRoundedRectangle(
            cornerRadii: RectangleCornerRadii(
                topLeading: outerRadius, bottomLeading: outerRadius,
                bottomTrailing: outerRadius, topTrailing: outerRadius
            ),
            style: .continuous
        )
        // Same reduced set as the live bar, minus the "+" — an archived week
        // can't be reacted to, so an affordance offering reactions nobody used
        // would be a control that does nothing.
        let reactions = layout.visible
        return HStack(spacing: 0) {
            ForEach(Array(reactions.enumerated()), id: \.element) { index, reaction in
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

                if index < reactions.count - 1 {
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

    /// Deliberately lists EVERY enabled reaction, overflow or not. At
    /// accessibility sizes the whole bar is already one menu, so there is no
    /// space to save — and a screen-reader or large-type user should never have
    /// a smaller vocabulary than anyone else.
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

    private func position(at index: Int, of total: Int) -> Position {
        if total == 1 { return .only }
        if index == 0 { return .first }
        if index == total - 1 { return .last }
        return .middle
    }

    private func displayCount(for reaction: Reaction) -> Int {
        counts[reaction] ?? 0
    }

    private enum Position {
        case first, middle, last, only

        func corners(outer: CGFloat, inner: CGFloat) -> RectangleCornerRadii {
            switch self {
            case .only:
                RectangleCornerRadii(
                    topLeading: outer,
                    bottomLeading: outer,
                    bottomTrailing: outer,
                    topTrailing: outer
                )
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
