//
//  AvatarView.swift
//  On Board
//

import SwiftUI
import Nuke
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
    /// First Class's Profile Colors perk — an accent ring, `nil` for the
    /// default neutral one. Only ever passed for the CURRENT user's own
    /// avatar (see `ProfileReadContent`); other profiles never set this, so
    /// there's no per-avatar entitlement lookup happening here.
    var tint: Color? = nil

    var body: some View {
        ZStack {
            // Flat fill rather than .thinMaterial — a blurred UIVisualEffectView
            // per avatar is wasted GPU at these sizes (up to ~30 on a feed screen).
            Circle()
                .fill(Color(.secondarySystemFill))
                .frame(width: size.diameter, height: size.diameter)
                .overlay(
                    Circle().stroke(tint ?? Color.secondary.opacity(0.3), lineWidth: tint == nil ? 1 : 2.5)
                )

            if let urlString = profile.avatarUrl, let url = URL(string: urlString) {
                LazyImage(request: OnBoardImagePipeline.request(url: url, width: size.diameter)) { state in
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
        // A Shape (Circle here) stretches to fill whatever rect it's actually
        // given — .frame only *proposes* a size. Most containers honor it
        // exactly, but toolbar items get bridged through UIBarButtonItem/
        // UIHostingController internals, which can propose a marginally wider
        // box (e.g. for a minimum tap-target width) than the frame asked for,
        // turning the circle into a very subtle ellipse. .fixedSize() forces
        // this view to use its own ideal size regardless of what any
        // container proposes, which is the correct contract for a
        // fixed-diameter avatar everywhere it's placed.
        .fixedSize()
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
