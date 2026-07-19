//
//  PopScoreView.swift
//  On Board
//
//  Reaction-distribution bar shown on profiles. Like/Dislike/Laugh/Hug map
//  onto the four hierarchical shape styles in order, reinforcing the
//  monochrome look while keeping each reaction visually distinct.
//

import SwiftUI

struct PopScoreView: View {
    let score: [Reaction: Int]

    var body: some View {
        let total = max(1, score.values.reduce(0, +))
        let sortedReactions = Reaction.defaultOrder.filter { (score[$0] ?? 0) > 0 }

        VStack(alignment: .leading, spacing: 12) {
            Text("Pop Score")
                .fontStyle(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            if score.isEmpty {
                Text("Post more to start building your score!")
                    .fontStyle(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        ForEach(sortedReactions, id: \.self) { reaction in
                            let count = score[reaction] ?? 0
                            // subtract 2 for the spacing to keep total width correct
                            let spacingCorrection = CGFloat(sortedReactions.count - 1) * 2.0 / CGFloat(sortedReactions.count)
                            let width = max(0, geo.size.width * CGFloat(count) / CGFloat(total) - spacingCorrection)
                            Rectangle()
                                .fill(style(for: reaction))
                                .frame(width: width)
                        }
                    }
                }
                .frame(height: 12)
                .clipShape(Capsule())

                HStack(spacing: 16) {
                    ForEach(sortedReactions, id: \.self) { reaction in
                        let count = score[reaction] ?? 0
                        HStack(spacing: 4) {
                            Text(reaction.emoji)
                            Text("\(count)")
                                .fontStyle(.caption2)
                                .fontWeight(.medium)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func style(for reaction: Reaction) -> AnyShapeStyle {
        switch reaction {
        case .like: return AnyShapeStyle(.primary)
        case .dislike: return AnyShapeStyle(.secondary)
        case .laugh: return AnyShapeStyle(.tertiary)
        case .hug: return AnyShapeStyle(.quaternary)
        }
    }
}
