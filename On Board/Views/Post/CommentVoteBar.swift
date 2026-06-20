//
//  CommentVoteBar.swift
//  On Board
//

import SwiftUI

struct CommentVoteBar: View {
    let likeCount: Int
    let dislikeCount: Int
    @Binding var selected: CommentVote?
    var isInteractive: Bool = true
    @AppStorage("hapticsEnabled") private var hapticsEnabled: Bool = true

    var body: some View {
        HStack(spacing: 8) {
            voteButton(.like, count: likeCount)
            voteButton(.dislike, count: dislikeCount)
        }
        .sensoryFeedback(trigger: selected) { _, _ in
            hapticsEnabled && isInteractive ? .impact(weight: .light) : nil
        }
        .allowsHitTesting(isInteractive)
        .opacity(isInteractive ? 1 : 0.85)
    }

    private func voteButton(_ vote: CommentVote, count: Int) -> some View {
        let isSelected = selected == vote
        return Button {
            guard isInteractive else { return }
            withAnimation(.smooth(duration: 0.2)) {
                selected = isSelected ? nil : vote
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isSelected ? vote.selectedSystemImage : vote.systemImage)
                    .fontStyle(.caption)
                Text(count.abbreviated)
                    .fontStyle(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .contentTransition(.numericText(value: Double(count)))
                    .animation(.snappy(duration: 0.35), value: count)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? Color.secondary.opacity(0.22) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(vote.label), \(count)")
    }
}
