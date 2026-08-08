//
//  ReactionStickerPill.swift
//  On Board
//

import SwiftUI

// MARK: - Reaction sticker pill

struct ReactionStickerPill: View {
    let reaction: Reaction
    let profile: Profile
    let tone: PostTone

    var body: some View {
        HStack(spacing: 3) {
            AvatarView(profile: profile, size: .xsmall)
            Text(reaction.emoji)
                .font(.system(size: 11))
        }
        .padding(3)
        .background(Capsule(style: .continuous).fill(tone.color))
        .allowsHitTesting(false)
    }
}
