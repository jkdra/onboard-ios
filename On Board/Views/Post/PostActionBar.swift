//
//  PostActionBar.swift
//  On Board
//
//  Reaction strip anchored to the bottom safe area of PostDetailView.
//

import SwiftUI

struct PostActionBar: View {
    let tone: PostTone
    let counts: [Reaction: Int]
    @Binding var selectedReaction: Reaction?
    var isInteractive: Bool = true
    var isRecord: Bool = false

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ReactionBar(
            counts: counts,
            tone: tone,
            selected: $selectedReaction,
            isInteractive: isInteractive,
            isRecord: isRecord
        )
        .safeAreaPadding()
        .background(barBackground)
    }

    @ViewBuilder
    private var barBackground: some View {
        if #available(iOS 26.0, *) {
            EmptyView()
        } else {
            Rectangle().fill(.bar)
                .ignoresSafeArea()
        }
    }
}
