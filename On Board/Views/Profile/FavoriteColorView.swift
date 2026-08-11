//
//  FavoriteColorView.swift
//  On Board
//
//  The Favorite Color row on a profile: the tone this user posts in most,
//  tallied server-side so it survives the weekly clear.
//
//  This is the one place on a profile where color is allowed to lead. The
//  brand is monochrome and the POSTS are the color, so a user's dominant
//  tone is the trace their posting leaves behind — showing it in anything
//  other than the tone itself would miss the whole point.
//

import SwiftUI

struct FavoriteColorView: View {
    let favorite: FavoriteTone

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Favorite Color")
                .fontStyle(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                // The swatch is a filled card, not a dot — it echoes the
                // masonry card the tone actually appears on.
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(favorite.tone.color)
                    .frame(width: 26, height: 26)

                Text(favorite.tone.displayName)
                    .fontStyle(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(favorite.tone.color)

                Spacer(minLength: 0)

                // The receipt. Without it the color is an assertion; with it,
                // it's earned — and it quietly says posting is what moves it.
                Text("\(favorite.count) of \(favorite.total) posts")
                    .fontStyle(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Favorite color: \(favorite.tone.displayName)")
        .accessibilityValue("\(favorite.count) of \(favorite.total) posts")
    }
}

#Preview("Dominant") {
    FavoriteColorView(favorite: FavoriteTone(tone: .orange, count: 14, total: 19))
        .padding()
}

#Preview("Just over the line") {
    FavoriteColorView(favorite: FavoriteTone(tone: .mint, count: 2, total: 6))
        .padding()
}
