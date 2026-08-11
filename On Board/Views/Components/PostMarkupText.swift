//
//  PostMarkupText.swift
//  On Board
//
//  Renders parsed post markup (PostMarkup.Block) for the two read surfaces:
//
//  * `PostMarkupText.cardText(_:)` — ONE concatenated `Text` for grid cards.
//    Concatenation is deliberate: a single `Text` can mix fonts per run while
//    a single `.lineLimit` still truncates across the *whole* post, which is
//    exactly the fixed-height masonry card's requirement. A VStack of Texts
//    would need a per-block line budget that can't know how many lines earlier
//    blocks actually wrapped to.
//
//  * `PostMarkupView` — the detail screen. Blocks become real views in a
//    VStack, so paragraph spacing and bullet indents are proper layout.
//
//  Both consume the same parse; neither ever sees a marker character.
//

import SwiftUI
import UIKit

// MARK: - Shared run styling

private extension Text {
    /// Applies the non-font inline traits. Italic is deliberately absent:
    /// the Zalando Sans family ships no italic face and no ital/slnt variable
    /// axis (verified against the TTFs' fvar tables), so SwiftUI's `.italic()`
    /// silently no-ops on it — caught on-simulator, not in review. Italic is
    /// instead synthesized at the font level; see `MarkupFont.resolve`.
    func applying(_ traits: InlineTraits) -> Text {
        var text = self
        if traits.contains(.bold) { text = text.bold() }
        if traits.contains(.underline) { text = text.underline() }
        if traits.contains(.strikethrough) { text = text.strikethrough() }
        return text
    }
}

/// Resolves a family + size to a Font, synthesizing an oblique when the run
/// is italic. For italic runs the weight must be baked into the descriptor
/// too — `Text.bold()` resolves via face lookup, which can't see a
/// matrix-skewed UIFont-backed Font.
private enum MarkupFont {
    static func resolve(
        family: String,
        size: CGFloat,
        relativeTo style: Font.TextStyle,
        traits: InlineTraits
    ) -> Font {
        guard traits.contains(.italic) else {
            return .custom(family, size: size, relativeTo: style)
        }
        // ~12° shear — the classic synthesized-oblique slant.
        let skew = CGAffineTransform(a: 1, b: 0, c: tan(CGFloat.pi / 15), d: 1, tx: 0, ty: 0)
        var attributes: [UIFontDescriptor.AttributeName: Any] = [
            .name: family,
            .matrix: skew,
        ]
        if traits.contains(.bold) {
            attributes[.traits] = [UIFontDescriptor.TraitKey.weight: UIFont.Weight.bold]
        }
        let base = UIFont(descriptor: UIFontDescriptor(fontAttributes: attributes), size: size)
        let scaled = UIFontMetrics(forTextStyle: uiTextStyle(style)).scaledFont(for: base)
        return Font(scaled)
    }

    private static func uiTextStyle(_ style: Font.TextStyle) -> UIFont.TextStyle {
        switch style {
        case .largeTitle: .largeTitle
        case .title: .title1
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .callout: .callout
        case .subheadline: .subheadline
        case .footnote: .footnote
        case .caption: .caption1
        case .caption2: .caption2
        default: .body
        }
    }
}

enum PostMarkupText {

    /// Card-scale fonts, matching the sizes GridCard used for its old
    /// title/description pair so existing cards look unchanged.
    private static func cardFont(
        for kind: PostBlockKind,
        traits: InlineTraits = [],
        tier: PostMarkup.BodyOnlyTier = .standard
    ) -> Font {
        switch kind {
        case .title:
            MarkupFont.resolve(family: "ZalandoSansExpanded-Regular", size: 16,
                               relativeTo: .title3, traits: traits)
        case .subtitle:
            MarkupFont.resolve(family: "ZalandoSansExpanded-Regular", size: 14,
                               relativeTo: .headline, traits: traits)
        case .body, .bullet:
            // Body-only cards lift off the 14pt base by the SAME steps the
            // detail scale uses (~1.18 / ~1.06) — enough that a short
            // body-only card reads as the main event in the masonry, small
            // enough that it never becomes a title. The 21/17 version this
            // replaces was the old editorial-headline ratio and shouted
            // across the grid.
            switch tier {
            case .extraLarge:
                MarkupFont.resolve(family: "ZalandoSansSemiExpanded-Regular", size: 16,
                                   relativeTo: .subheadline, traits: traits)
            case .large:
                MarkupFont.resolve(family: "ZalandoSansSemiExpanded-Regular", size: 15,
                                   relativeTo: .callout, traits: traits)
            case .standard:
                MarkupFont.resolve(family: "ZalandoSansSemiExpanded-Regular", size: 14,
                                   relativeTo: .callout, traits: traits)
            }
        }
    }

    /// Body emphasis (research-tuned, 2026-08-06): `.secondary` composites to
    /// ~3.4:1 on light backgrounds — BELOW WCAG AA for 14pt regular text, and
    /// worse on tinted cards. Design-system consensus for card body copy is
    /// the 0.75–0.82 band (Primer #59636e, Polaris #616161, M3
    /// onSurfaceVariant), hence primary at 0.78. And a card with NO heading
    /// renders its body at FULL primary — X/Threads/Mastodon never render
    /// post content as supporting text; the body IS the headline there.
    private static let headedBodyOpacity = 0.78

    /// One concatenated Text for the whole post. The caller applies the global
    /// `lineLimit` / `truncationMode` (plus `.lineSpacing(2.5)` — lands 14pt
    /// text at ~1.36 line ratio, between HIG and Material's 14/20).
    static func cardText(_ markup: PostMarkup) -> Text {
        let hasHeading = markup.blocks.contains { $0.kind == .title || $0.kind == .subtitle }
        let bodyColor: Color = hasHeading ? .primary.opacity(headedBodyOpacity) : .primary
        let tier = markup.bodyOnlyTier

        var result = Text(verbatim: "")
        var isFirst = true
        var previousKind: PostBlockKind?
        for block in markup.blocks {
            // Skip fully-empty body lines at card scale — a blank spacer line
            // is rhythm the card doesn't have room for, and it burns a line of
            // the shared truncation budget.
            if block.kind == .body, block.plainText.isEmpty { continue }

            if !isFirst {
                result = result + Text(verbatim: "\n")
                // Paragraph gap after a heading (~6pt visual): a blank-line run
                // at 4pt — 0.5em convention scaled to card density. Costs one
                // line of the truncation budget; the anchor is worth it.
                if previousKind == .title || previousKind == .subtitle {
                    result = result + Text(verbatim: "\n").font(.system(size: 4))
                }
            }
            isFirst = false
            previousKind = block.kind

            if block.kind == .bullet {
                result = result + Text(verbatim: "•  ").font(cardFont(for: .bullet)).foregroundColor(bodyColor)
            }
            for run in block.runs {
                var segment = Text(verbatim: run.text)
                    .font(cardFont(for: block.kind, traits: run.traits, tier: tier))
                    .applying(run.traits)
                if run.traits.contains(.tag) {
                    // ONE differentiating cue (weight), like every platform —
                    // at body opacity, so a hashtag line can't outshout a
                    // 16pt heavy heading two lines up.
                    segment = segment.fontWeight(.semibold).foregroundColor(bodyColor)
                } else {
                    switch block.kind {
                    case .title:
                        segment = segment.fontWeight(.heavy).foregroundColor(.primary)
                    case .subtitle:
                        segment = segment.fontWeight(.semibold).foregroundColor(.primary)
                    case .body, .bullet:
                        segment = segment.foregroundColor(bodyColor)
                    }
                }
                result = result + segment
            }
        }
        return result
    }
}

// MARK: - Detail-scale block view

/// Full-size rendering for PostDetailView: titles at display scale, real
/// paragraph spacing, hanging bullet indents.
struct PostMarkupView: View {
    let markup: PostMarkup

    init(content: String) {
        self.markup = PostMarkup.cached(content)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(markup.blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
    }

    @ViewBuilder
    private func blockView(_ block: PostMarkup.Block) -> some View {
        if block.kind == .body, block.plainText.isEmpty {
            // A deliberate blank line: honoured as breathing room at detail
            // scale (unlike cards, where space is budgeted).
            Color.clear.frame(height: 2)
        } else if block.kind == .bullet {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: "•")
                    .fontStyle(.body)
                    .foregroundStyle(.secondary)
                inlineText(block)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, 4)
        } else {
            inlineText(block)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(block.kind == .body ? 3 : 0)
        }
    }

    private func inlineText(_ block: PostMarkup.Block) -> Text {
        var result = Text(verbatim: "")
        for run in block.runs {
            var segment = Text(verbatim: run.text)
                .font(detailFont(for: block.kind, traits: run.traits, tier: markup.bodyOnlyTier))
                .applying(run.traits)
            if run.traits.contains(.tag) {
                segment = segment.fontWeight(.semibold)
            }
            result = result + segment
        }
        switch block.kind {
        case .title: return result.fontWeight(.bold)
        case .subtitle: return result.fontWeight(.semibold)
        case .body, .bullet: return result
        }
    }

    /// Detail-scale fonts. Title matches the old post-title treatment
    /// (`fontStyle(.largeTitle)`), body matches `fontStyle(.body)`.
    private func detailFont(
        for kind: PostBlockKind,
        traits: InlineTraits = [],
        tier: PostMarkup.BodyOnlyTier = .standard
    ) -> Font {
        switch kind {
        case .title:
            MarkupFont.resolve(family: "ZalandoSansExpanded-Regular", size: 30,
                               relativeTo: .largeTitle, traits: traits)
        case .subtitle:
            MarkupFont.resolve(family: "ZalandoSansExpanded-Regular", size: 18,
                               relativeTo: .title2, traits: traits)
        case .body, .bullet:
            // Body-only emphasis is a UI step, not an editorial headline.
            // Type-scale convention splits the two: ~1.125–1.2 (minor
            // third) for UI hierarchy, 1.333–1.5 (fourth/fifth) only where
            // a big H1 is the deliberate focal point. This shipped at 26pt
            // on a 17pt body — 1.53×, exactly the editorial-H1 ratio — and
            // read as a title, which is the one thing a body-only post is
            // not. 20pt is one minor-third step (1.18×) and lands on
            // Apple's own next rung above body (title3); `large` takes the
            // half step. Tiers only apply when the author added NO heading
            // (bodyOnlyTier stands down otherwise), so this never competes
            // with the 30pt title above.
            switch tier {
            case .extraLarge:
                MarkupFont.resolve(family: "ZalandoSansSemiExpanded-Regular", size: 20,
                                   relativeTo: .title3, traits: traits)
            case .large:
                MarkupFont.resolve(family: "ZalandoSansSemiExpanded-Regular", size: 18,
                                   relativeTo: .body, traits: traits)
            case .standard:
                MarkupFont.resolve(family: "ZalandoSansSemiExpanded-Regular", size: 17,
                                   relativeTo: .body, traits: traits)
            }
        }
    }
}

#Preview("Markup rendering") {
    ScrollView {
        VStack(alignment: .leading, spacing: 24) {
            PostMarkupView(content: """
            # lost: black hydroflask
            last seen in the **dc basement** near the vending machines
            ## reward
            * my eternal gratitude
            * a ~~firm handshake~~ high five
            it has *exactly* 47 stickers on it

            #lost-and-found #dc
            """)
            Divider()
            PostMarkupText.cardText(PostMarkup.parse("""
            # the oat milk situation
            if my roommate drinks my oat milk **one more time** im genuinely going to ~~lose it~~ have a calm conversation
            """))
            .lineLimit(7)
        }
        .padding()
    }
}
