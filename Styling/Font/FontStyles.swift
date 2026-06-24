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
            case .headline:.semibold
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
            case .largeTitle: Font.TextStyle.largeTitle
            case .title: Font.TextStyle.title
            case .title2: Font.TextStyle.title2
            case .title3: Font.TextStyle.title3
            case .headline: Font.TextStyle.headline
            case .body: Font.TextStyle.body
            case .callout: Font.TextStyle.callout
            case .subheadline: Font.TextStyle.subheadline
            case .footnote: Font.TextStyle.footnote
            case .caption: Font.TextStyle.caption
            case .caption2: Font.TextStyle.caption2
        }
    }
}

extension View {
    public func fontStyle(_ style: FontStyle) -> some View {
        self
            .font(.custom(fontName, size: style.size, relativeTo: style.originalStyle))
            .fontWeight(style.weight)
            .opacity(style.opacity)
    }
}

