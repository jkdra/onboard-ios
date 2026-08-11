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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("hapticsEnabled") private var hapticsEnabled: Bool = true

    /// Transient face on the overflow slot — see `peekCandidate`. Driven by
    /// the one-shot `.task` below; never persisted, never announced.
    @State private var peekedReaction: Reaction?

    private let outerRadius: CGFloat = 32
    private let innerRadius: CGFloat = 4
    private let interButtonSpacing: CGFloat = 4

    /// How many reactions are permanent pills under the overflow layout. The
    /// split is positional, so `enabledReactions`' ORDER decides which two —
    /// reorder the config value to change them, don't special-case a case here.
    static let permanentCount = 2

    // MARK: - What the strip renders

    /// The bar's slots.
    ///
    /// **Counts are not an input.** The strip's shape is a function of config
    /// and of the viewer's own selection — never of how other people reacted.
    /// A slot that changes identity because a post got popular is a control
    /// that means something different on every post, and no one can build a
    /// habit against that. Layout adapts to user CONTENT; controls hold still.
    ///
    /// So: the first two reactions are always the first two pills, and the
    /// overflow slot is always in the same place doing the same job — open a
    /// menu. All that changes is its face, which reflects what *you* picked.
    ///
    /// Pure and `internal` so the tests drive this exact code rather than a
    /// copy of it.
    static func slots(
        enabled: [Reaction],
        selected: Reaction?,
        overflowEnabled: Bool
    ) -> Slots {
        guard overflowEnabled, enabled.count > permanentCount else {
            return Slots(permanent: enabled, overflow: [], overflowFace: nil)
        }
        let overflow = Array(enabled.dropFirst(permanentCount))
        return Slots(
            permanent: Array(enabled.prefix(permanentCount)),
            overflow: overflow,
            // Only an overflow reaction can wear the slot; picking `like`
            // leaves it a plus, because `like` has its own pill.
            overflowFace: selected.flatMap { overflow.contains($0) ? $0 : nil }
        )
    }

    struct Slots: Equatable {
        /// Always-present pills, in config order.
        let permanent: [Reaction]
        /// What the overflow menu offers. Empty means no overflow slot at all.
        let overflow: [Reaction]
        /// The reaction the overflow slot is currently wearing; `nil` shows the
        /// plus. Driven by selection only.
        let overflowFace: Reaction?

        var hasOverflow: Bool { !overflow.isEmpty }
        /// Rendered slot count, for the strip's corner radii.
        var total: Int { permanent.count + (hasOverflow ? 1 : 0) }
    }

    private var slots: Slots {
        Self.slots(
            enabled: enabledReactions,
            selected: selected,
            overflowEnabled: reactionOverflowEnabled
        )
    }

    // MARK: - The peek

    /// Which overflow reaction (if any) the "+" briefly peeks on appearance —
    /// a post where laugh is doing real work hints that more reactions live
    /// behind the menu, without the slot ever *being* anything but the menu
    /// button. Thresholds are RELATIVE (share of the post's total) plus a
    /// small floor: an absolute cutoff behaves completely differently on a
    /// board of 15 and a board of 500.
    ///
    /// This is the one place counts may influence the overflow slot, and only
    /// its transient FACE — never its identity, position, or behavior. The
    /// layout rule (`slots` takes no counts) stays intact.
    static func peekCandidate(
        overflow: [Reaction],
        counts: [Reaction: Int]
    ) -> Reaction? {
        let total = counts.values.reduce(0, +)
        guard total >= 5 else { return nil }
        let best = overflow
            .compactMap { reaction in counts[reaction].map { (reaction, $0) } }
            .max { $0.1 < $1.1 }
        guard let best, best.1 >= 3, Double(best.1) / Double(total) >= 0.15 else { return nil }
        return best.0
    }

    var body: some View {
        reactionStrip
            .sensoryFeedback(trigger: selected) { _, _ in
                hapticsEnabled && isInteractive && !isRecord ? .impact(weight: .light) : nil
            }
            .allowsHitTesting(isInteractive && !isRecord)
            .opacity(isRecord ? 1 : (isInteractive ? 1 : 0.85))
            .task {
                // The peek: ~2s of the post's dominant overflow reaction, at
                // reduced opacity, on the "+" — then back. ONE-SHOT per
                // appearance (`.task` cancels on disappear; nothing loops,
                // per the repeatForever/UI-test lesson), only when nothing is
                // selected (a dimmed peek and a tinted selection are the same
                // emoji — gating on `overflowFace == nil` is what keeps them
                // unambiguous), and skipped entirely under Reduce Motion.
                guard reactionOverflowEnabled, isInteractive, !isRecord, !reduceMotion,
                      !typeSize.isAccessibilitySize else { return }
                let slots = self.slots
                guard slots.hasOverflow, slots.overflowFace == nil,
                      let candidate = Self.peekCandidate(overflow: slots.overflow, counts: counts)
                else { return }
                try? await Task.sleep(for: .seconds(0.8))
                guard !Task.isCancelled, self.slots.overflowFace == nil else { return }
                withAnimation(.smooth(duration: 0.35)) { peekedReaction = candidate }
                try? await Task.sleep(for: .seconds(2))
                withAnimation(.smooth(duration: 0.35)) { peekedReaction = nil }
            }
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
            let slots = self.slots
            HStack(spacing: interButtonSpacing) {
                ForEach(Array(slots.permanent.enumerated()), id: \.element) { index, reaction in
                    button(for: reaction, position: position(at: index, of: slots.total))
                }
                if slots.hasOverflow {
                    overflowMenu(slots, position: position(at: slots.total - 1, of: slots.total))
                }
            }
        }
    }

    /// The third control: always here, always opens the same menu.
    ///
    /// Wears a filled plus until you pick something from it, then wears that
    /// reaction and its count — but it is still the same button in the same
    /// place, so tapping it again reopens the menu to switch, or to tap your
    /// current pick and clear it.
    ///
    /// A `Menu` rather than a long-press on another pill: a hidden gesture is
    /// invisible to VoiceOver, and would have to win arbitration against
    /// `DoubleTapHeart` and the zoom transition's interactive pop on the same
    /// card.
    private func overflowMenu(_ slots: Slots, position: Position) -> some View {
        let face = slots.overflowFace
        let shape = UnevenRoundedRectangle(
            cornerRadii: position.corners(outer: outerRadius, inner: innerRadius),
            style: .continuous
        )
        return Menu {
            // Counts live HERE, for every overflow reaction, whether or not
            // one is picked — one predictable place to read them, rather than
            // a pill that only sometimes exists.
            ForEach(slots.overflow, id: \.self) { reaction in
                Button {
                    guard isInteractive else { return }
                    withAnimation(.smooth(duration: 0.2)) {
                        selected = selected == reaction ? nil : reaction
                    }
                } label: {
                    Label(
                        "\(reaction.emoji)  \(reaction.label)  \(displayCount(for: reaction).abbreviated)",
                        systemImage: selected == reaction ? "checkmark" : ""
                    )
                }
            }
        } label: {
            HStack(spacing: 6) {
                if let face {
                    Text(face.emoji)
                        .fontStyle(.caption)
                    Text(displayCount(for: face).abbreviated)
                        .fontStyle(.caption)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .contentTransition(.numericText(value: Double(displayCount(for: face))))
                        .animation(.snappy(duration: 0.35), value: displayCount(for: face))
                } else {
                    // Plus and peek layered so the swap is a pure crossfade —
                    // no layout change, no width shift. The peek is a HINT:
                    // dimmed enough that it can't read as a selected state
                    // (selection is full-opacity on a tinted pill).
                    ZStack {
                        Image(systemName: "plus.circle.fill")
                            .fontStyle(.caption)
                            .opacity(peekedReaction == nil ? 1 : 0)
                        if let peeked = peekedReaction {
                            Text(peeked.emoji)
                                .fontStyle(.caption)
                                .opacity(0.55)
                                .transition(.opacity)
                        }
                    }
                }
            }
            .foregroundStyle(face != nil ? tone.legibleForeground : .primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical)
            .contentShape(shape)
            .background(reactionBackground(shape: shape, isSelected: face != nil))
        }
        .disabled(!isInteractive)
        .accessibilityLabel(face.map { "\($0.label), \(displayCount(for: $0)), selected" } ?? "More reactions")
    }

    private var recordLayout: some View {
        let shape = UnevenRoundedRectangle(
            cornerRadii: RectangleCornerRadii(
                topLeading: outerRadius, bottomLeading: outerRadius,
                bottomTrailing: outerRadius, topTrailing: outerRadius
            ),
            style: .continuous
        )
        // Untouched by the overflow layout: this is a RECORD, not a control.
        // Nothing here is tappable, so there is no habit to protect and no
        // menu to hide anything behind — an archived week just shows what the
        // board actually did, every reaction and its final count.
        let reactions = enabledReactions
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
