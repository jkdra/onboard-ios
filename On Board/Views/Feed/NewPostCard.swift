//
//  NewPostCard.swift
//  On Board
//

import SwiftUI

struct NewPostCard: View {
    var columnWidth: CGFloat = 0
    /// When false (the final hour before the board clears), the card stays in the
    /// grid but reads as closed — a clock glyph and "Clears soon" instead of the
    /// tappable plus. Height is identical either way so the masonry never reflows.
    var isEnabled: Bool = true

    @Environment(\.dynamicTypeSize) private var typeSize

    private var cardHeight: CGFloat {
        if typeSize.isAccessibilitySize { return 300 }
        let idealHeight = columnWidth * 1.15
        return max(180, min(idealHeight, 260))
    }

    let strokeStyle: StrokeStyle = .init(lineWidth: 4, lineCap: .round, dash: [12])

    var body: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .stroke(style: strokeStyle)
            .foregroundStyle(.secondary.opacity(isEnabled ? 0.45 : 0.25))
            .frame(height: cardHeight)
            .overlay {
                if isEnabled { enabledContent } else { disabledContent }
            }
    }

    private var enabledContent: some View {
        ZStack {
            Circle()
                .fill(.secondary.opacity(0.18))
                .frame(width: 84, height: 84)
            Image(systemName: "plus")
                .fontStyle(.title)
                .foregroundStyle(.secondary)
        }
    }

    private var disabledContent: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(.secondary.opacity(0.10))
                    .frame(width: 84, height: 84)
                Image(systemName: "clock")
                    .fontStyle(.title)
                    .foregroundStyle(.secondary.opacity(0.6))
            }
            Text("Clears soon")
                .fontStyle(.subheadline)
                .foregroundStyle(.secondary.opacity(0.6))
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 12)
    }
}
