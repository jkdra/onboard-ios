//
//  FeedGridCard.swift
//  On Board
//

import SwiftUI

/// Resolves a feed card from the store by ID so reaction and tone updates re-render only this cell.
struct FeedGridCard: View {
    let postID: UUID
    var cardNamespace: Namespace.ID? = nil
    var transitionID: BoardRoute? = nil
    var cardRotation: Double = 0
    var isLeadingColumn: Bool = false
    var columnWidth: CGFloat = 0
    @Environment(BoardStore.self) private var store
    @AppStorage("rotationIntensity") private var rotationIntensity: Double = 0.6

    var body: some View {
        if let proxy = store.postProxies[postID] {
            GridCard(
                post: proxy.post,
                userReaction: proxy.reaction,
                currentUser: store.currentUser,
                authorProfile: store.profile(forAuthor: proxy.post.author),
                cardNamespace: cardNamespace,
                transitionID: transitionID,
                cardRotation: cardRotation,
                rotationIntensity: rotationIntensity,
                isLeadingColumn: isLeadingColumn,
                columnWidth: columnWidth
            )
            // id is the post alone — including tone here would force a full
            // remount on every tone change, which destroys and recreates the
            // view AT the new color, so the `.animation(value: post.tone)`
            // modifiers below (textCard/imageCard) never see an old value to
            // cross-fade from and the tone change hard-cuts instead.
            .id(postID.uuidString)
        }
    }
}
