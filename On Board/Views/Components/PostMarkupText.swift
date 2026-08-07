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
    private static func cardFont(for kind: PostBlockKind, traits: InlineTraits = []) -> Font {
        switch kind {
        case .title:
            MarkupFont.resolve(family: "ZalandoSansExpanded-Regular", size: 16,
                               relativeTo: .title3, traits: traits)
        case .subtitle:
            MarkupFont.resolve(family: "ZalandoSansExpanded-Regular", size: 14,
                               relativeTo: .headline, traits: traits)
        case .body, .bullet:
            MarkupFont.resolve(family: "ZalandoSansSemiExpanded-Regular", size: 14,
                               relativeTo: .callout, traits: traits)
        }
    }

    /// One concatenated Text for the whole post. The caller applies the global
    /// `lineLimit` / `truncationMode`.
    static func cardText(_ markup: PostMarkup) -> Text {
        var result = Text(verbatim: "")
        var isFirst = true
        for block in markup.blocks {
            // Skip fully-empty body lines at card scale — a blank spacer line
            // is rhythm the card doesn't have room for, and it burns a line of
            // the shared truncation budget.
            if block.kind == .body, block.plainText.isEmpty { continue }

            if !isFirst { result = result + Text(verbatim: "\n") }
            isFirst = false

            if block.kind == .bullet {
                result = result + Text(verbatim: "•  ").font(cardFont(for: .bullet)).foregroundColor(.secondary)
            }
            for run in block.runs {
                var segment = Text(verbatim: run.text)
                    .font(cardFont(for: block.kind, traits: run.traits))
                    .applying(run.traits)
                switch block.kind {
                case .title:
                    segment = segment.fontWeight(.heavy).foregroundColor(.primary)
                case .subtitle:
                    segment = segment.fontWeight(.semibold).foregroundColor(.primary)
                case .body, .bullet:
                    segment = segment.foregroundColor(.secondary)
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
        self.markup = PostMarkup.parse(content)
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
        }
    }

    private func inlineText(_ block: PostMarkup.Block) -> Text {
        var result = Text(verbatim: "")
        for run in block.runs {
            result = result + Text(verbatim: run.text)
                .font(detailFont(for: block.kind, traits: run.traits))
                .applying(run.traits)
        }
        switch block.kind {
        case .title: return result.fontWeight(.bold)
        case .subtitle: return result.fontWeight(.semibold)
        case .body, .bullet: return result
        }
    }

    /// Detail-scale fonts. Title matches the old post-title treatment
    /// (`fontStyle(.largeTitle)`), body matches `fontStyle(.body)`.
    private func detailFont(for kind: PostBlockKind, traits: InlineTraits = []) -> Font {
        switch kind {
        case .title:
            MarkupFont.resolve(family: "ZalandoSansExpanded-Regular", size: 30,
                               relativeTo: .largeTitle, traits: traits)
        case .subtitle:
            MarkupFont.resolve(family: "ZalandoSansExpanded-Regular", size: 18,
                               relativeTo: .title2, traits: traits)
        case .body, .bullet:
            MarkupFont.resolve(family: "ZalandoSansSemiExpanded-Regular", size: 17,
                               relativeTo: .body, traits: traits)
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
