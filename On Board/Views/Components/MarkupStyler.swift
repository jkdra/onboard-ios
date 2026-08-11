//
//  MarkupStyler.swift
//  On Board
//
//  Split out of MarkupTextEditor.swift. See that file's header for the
//  composer's invariant and the five rules.
//

import SwiftUI
import UIKit

// MARK: - Styling

/// UIKit mirror of PostMarkupText's font logic: same families, same
/// composer-appropriate scale, same synthesized oblique for the italic the
/// Zalando family doesn't ship.
enum MarkupStyler {
    static let baseFont = UIFont(name: "ZalandoSansSemiExpanded-Regular", size: 17)
        ?? .systemFont(ofSize: 17)

    /// Body point size for a body-only draft, mirroring
    /// PostMarkupText.detailFont's tiers so the composer shows the size the
    /// post will actually publish at. Adding a `# title` or `## subtitle`
    /// makes bodyOnlyTier stand down, so the body visibly settles back to
    /// 17pt as the author types the heading — the size IS the feedback that
    /// the structure took.
    static func bodySize(for tier: PostMarkup.BodyOnlyTier) -> CGFloat {
        switch tier {
        case .extraLarge: 20
        case .large: 18
        case .standard: 17
        }
    }

    static func baseAttributes(tier: PostMarkup.BodyOnlyTier = .standard) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        let size = bodySize(for: tier)
        let font = UIFont(name: "ZalandoSansSemiExpanded-Regular", size: size)
            ?? .systemFont(ofSize: size)
        return [.font: font, .foregroundColor: UIColor.label, .paragraphStyle: paragraph]
    }

    static func attributes(
        for span: PostMarkup.Span,
        tier: PostMarkup.BodyOnlyTier = .standard
    ) -> [NSAttributedString.Key: Any] {
        var attributes = baseAttributes(tier: tier)
        attributes[.font] = font(kind: span.blockKind, traits: span.traits, tier: tier)
        if span.isMarker {
            // The dim that makes the syntax feel inert: visible enough to
            // edit, quiet enough that the CONTENT reads as the post.
            attributes[.foregroundColor] = UIColor.label.withAlphaComponent(0.32)
        } else {
            if span.traits.contains(.strikethrough) {
                attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            }
            if span.traits.contains(.underline) {
                attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            }
        }
        return attributes
    }

    private static func font(
        kind: PostBlockKind,
        traits: InlineTraits,
        tier: PostMarkup.BodyOnlyTier = .standard
    ) -> UIFont {
        let (family, size, baseWeight): (String, CGFloat, UIFont.Weight?) = switch kind {
        case .title: ("ZalandoSansExpanded-Regular", 26, .heavy)
        case .subtitle: ("ZalandoSansExpanded-Regular", 19, .semibold)
        case .body, .bullet: ("ZalandoSansSemiExpanded-Regular", bodySize(for: tier), nil)
        }
        var weight = baseWeight
        if traits.contains(.bold) { weight = .bold }
        if traits.contains(.tag), weight == nil { weight = .semibold }

        let base = UIFont(name: family, size: size) ?? .systemFont(ofSize: size)
        var descriptor = base.fontDescriptor
        var attributes: [UIFontDescriptor.AttributeName: Any] = [:]
        if let weight {
            // These are VARIABLE fonts (wght axis, verified in the TTFs'
            // fvar tables) — a UIFontDescriptor weight trait silently no-ops
            // on them; drive the axis directly. Caught on-simulator: the
            // title rendered regular-weight while italic's matrix worked.
            let wghtAxis = 0x77676874 // 'wght'
            let value: CGFloat = switch weight {
            case .heavy: 800
            case .bold: 700
            default: 600
            }
            let variationKey = UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String)
            attributes[variationKey] = [wghtAxis: value]
        }
        if traits.contains(.italic) {
            attributes[.matrix] = CGAffineTransform(a: 1, b: 0, c: tan(CGFloat.pi / 15), d: 1, tx: 0, ty: 0)
        }
        if !attributes.isEmpty {
            descriptor = descriptor.addingAttributes(attributes)
        }
        return UIFont(descriptor: descriptor, size: size)
    }
}
