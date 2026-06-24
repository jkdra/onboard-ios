//
//  AvatarView.swift
//  On Board
//

import SwiftUI
import NukeUI

enum AvatarSize {
    case xsmall  // 24pt  — inline comments, grid cards
    case small   // 32pt  — post headers, reply composers
    case medium  // 52pt
    case large   // 92pt

    var diameter: CGFloat {
        switch self {
        case .xsmall: 24
        case .small: 32
        case .medium: 52
        case .large: 92
        }
    }

    var iconSize: CGFloat {
        switch self {
        case .xsmall: 14
        case .small: 18
        case .medium: 30
        case .large: 52
        }
    }
}

struct AvatarView: View {
    let profile: Profile
    var size: AvatarSize = .medium

    var body: some View {
        ZStack {
            Circle()
                .fill(.thinMaterial)
                .frame(width: size.diameter, height: size.diameter)
                .overlay(
                    Circle().stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )

            if let urlString = profile.avatarUrl, let url = URL(string: urlString) {
                LazyImage(url: url) { state in
                    if let image = state.image {
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: size.diameter, height: size.diameter)
                            .clipShape(Circle())
                    } else {
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size.diameter, height: size.diameter)
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        Image(systemName: "person.circle.fill")
            .resizable()
            .scaledToFit()
            .frame(width: size.iconSize, height: size.iconSize)
            .foregroundStyle(Color.secondary.opacity(0.5))
    }
}
