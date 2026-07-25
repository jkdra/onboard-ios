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
    }

    private func voteButton(_ vote: CommentVote, count: Int) -> some View {
        let isSelected = selected == vote
        // Archived (read-only) week: icons are shown FILLED but dimmed — a faded
        // record of what happened — and the viewer's own pick is marked with a
        // capsule stroke instead of a fill (kept crisp, above the dim).
        let archived = !isInteractive
        return Button {
            guard isInteractive else { return }
            withAnimation(.smooth(duration: 0.2)) {
                selected = isSelected ? nil : vote
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: (archived || isSelected) ? vote.selectedSystemImage : vote.systemImage)
                    .fontStyle(.caption)
                Text(count.abbreviated)
                    .fontStyle(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .contentTransition(.numericText(value: Double(count)))
                    .animation(.snappy(duration: 0.35), value: count)
            }
            .opacity(archived ? 0.5 : 1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background {
                if archived {
                    Capsule(style: .continuous)
                        .strokeBorder(Color.secondary.opacity(isSelected ? 0.55 : 0), lineWidth: 1.5)
                } else {
                    Capsule(style: .continuous)
                        .fill(isSelected ? Color.secondary.opacity(0.22) : Color.clear)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(vote.label), \(count)")
    }
}
