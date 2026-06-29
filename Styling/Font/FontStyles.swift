//
//  FontStyles.swift
//  demonstrate
//
//  Created by Jawad Khadra on 6/16/26.
//

import Foundation
import SwiftUI

public enum FontStyle {
    case largeTitle, title, title2, title3, headline, body, callout, subheadline, footnote, caption, caption2

    var size: CGFloat {
        switch self {
            case .largeTitle: return 30
            case .title: return 24
            case .title2: return 18
            case .title3: return 16
            case .headline: return 17
            case .body: return 17
            case .callout: return 16
            case .subheadline: return 15
            case .footnote: return 13
            case .caption: return 12
            case .caption2: return 10
        }
    }

    var weight: Font.Weight {
        switch self {
            case .largeTitle: .bold
            case .title: .bold
            case .title2: .regular
            case .title3: .bold
            case .headline: .semibold
            case .body: .regular
            case .callout: .regular
            case .subheadline: .semibold
            case .footnote: .regular
            case .caption: .regular
            case .caption2: .regular
        }
    }

    var opacity: Double {
        switch self {
            case .largeTitle: 1
            case .title: 1
            case .title2: 1
            case .title3: 1
            case .headline: 1
            case .body: 0.8
            case .callout: 0.8
            case .subheadline: 1
            case .footnote: 0.5
            case .caption: 1
            case .caption2: 1
        }
    }

    var originalStyle: Font.TextStyle {
        switch self {
            case .largeTitle: .largeTitle
            case .title: .title
            case .title2: .title2
            case .title3: .title3
            case .headline: .headline
            case .body: .body
            case .callout: .callout
            case .subheadline: .subheadline
            case .footnote: .footnote
            case .caption: .caption
            case .caption2: .caption2
        }
    }

    // Expanded for title-tier styles; standard for body/UI text.
    var fontFamilyName: String {
        switch self {
            case .largeTitle, .title, .title2, .title3, .headline:
                return "ZalandoSansExpanded-Regular"
            case .body, .callout, .subheadline, .footnote, .caption, .caption2:
                return "ZalandoSansSemiExpanded-Regular"
        }
    }
}

private struct FontStyleModifier: ViewModifier {
    let style: FontStyle

    // Reflects the system "Increase Contrast" accessibility setting. When it's on,
    // we drop the decorative opacity reduction (footnote 0.5, body/callout 0.8) and
    // render text at full opacity so low-contrast text meets the user's request.
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content
            .font(.custom(style.fontFamilyName, size: style.size, relativeTo: style.originalStyle))
            .fontWeight(style.weight)
            .opacity(contrast == .increased ? 1 : style.opacity)
    }
}

extension View {
    public func fontStyle(_ style: FontStyle) -> some View {
        modifier(FontStyleModifier(style: style))
    }
}
