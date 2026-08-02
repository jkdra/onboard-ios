//
//  PromotedSlot.swift
//  On Board
//
//  Owns one promoted slot's lifecycle: reserve the space, resolve an ad into it,
//  and fall back to the house promo when nothing fills.
//
//  Split from `AdCard` on purpose. The card is a pure function of its content —
//  previewable, testable, no async. This holds the loading state, so the two can be
//  reasoned about (and broken) independently.
//
//  The slot never changes height. It is `AdCard.cardHeight` from first render,
//  through loading, to filled-or-house-promo. `BoardFeedView.estimatedHeight` knows
//  that height too, so column balancing is settled before any ad exists — no reflow,
//  which is the failure mode the roadmap calls the most-hated of all.
//

import SwiftUI

struct PromotedSlot: View {
    let slot: Int
    let weekID: UUID
    var columnWidth: CGFloat = 0

    @Environment(\.nativeAdProvider) private var provider

    @State private var content: NativeAdContent?
    @State private var didResolve = false

    var body: some View {
        Group {
            if didResolve {
                AdCard(content: content, columnWidth: columnWidth)
            } else {
                placeholder
            }
        }
        // Re-resolve per slot per week: the id changes on rollover, so a new board
        // never shows the previous week's ad.
        .task(id: "\(weekID.uuidString)-\(slot)") {
            didResolve = false
            content = await provider.loadAd()
            guard !Task.isCancelled else { return }
            withAnimation(.smooth(duration: 0.3)) { didResolve = true }
        }
    }

    /// Same height, same corner radius, no content. Neutral rather than a shimmer:
    /// an animated skeleton advertises that something is coming, and drawing the eye
    /// to an ad before it arrives is the opposite of the intent.
    private var placeholder: some View {
        RoundedRectangle(cornerRadius: AdCard.cornerRadius, style: .continuous)
            .fill(.primary.opacity(0.04))
            .frame(height: AdCard(content: nil, columnWidth: columnWidth).cardHeight)
            .overlay {
                RoundedRectangle(cornerRadius: AdCard.cornerRadius, style: .continuous)
                    .stroke(.primary.opacity(0.14), lineWidth: 1.5)
            }
            .accessibilityHidden(true)
    }
}

// MARK: - Environment seam

private struct NativeAdProviderKey: EnvironmentKey {
    static let defaultValue: any NativeAdProvider = MockNativeAdProvider()
}

extension EnvironmentValues {
    /// Injected at the root (see `On_BoardApp`). Defaults to the mock so previews
    /// and mock builds render real-looking slots with no SDK, no ad unit ID, and no
    /// network — the same seam pattern the auth/board/subscription services use.
    var nativeAdProvider: any NativeAdProvider {
        get { self[NativeAdProviderKey.self] }
        set { self[NativeAdProviderKey.self] = newValue }
    }
}

#Preview("Promoted slot") {
    HStack(alignment: .top, spacing: 12) {
        PromotedSlot(slot: 0, weekID: UUID(), columnWidth: 174)
        PromotedSlot(slot: 1, weekID: UUID(), columnWidth: 174)
    }
    .padding(16)
    .background(Color(.systemGroupedBackground))
}
