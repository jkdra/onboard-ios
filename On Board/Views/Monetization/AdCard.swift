//
//  AdCard.swift
//  On Board
//
//  The promoted slot's card. Renders a `NativeAdContent`, or the First Class house
//  promo when the slot goes unfilled.
//
//  ## Why this looks nothing like GridCard
//
//  It is deliberately *chrome*, not content. A post card is tone-tinted, glassy,
//  pinned at a slight angle, and 18pt-rounded; this is monochrome, flat, square-on,
//  and 10pt-rounded. The corner radius does more work than anything else here —
//  it reads as a different class of object pre-consciously, before the label or the
//  absence of colour registers. That matters because the First Class pitch isn't
//  "fewer ads", it's "your board is only your campus again", which only lands if
//  ads are visibly not-of-the-board.
//
//  An earlier pass borrowed GridCard's image-bundle treatment (media tucked over a
//  card, CTA overhanging like the reaction sticker). It was dropped: the bundle is
//  the board's most native structure, so lending it to foreign inventory said
//  "I belong" with the layout while the palette said the opposite. That grammar is
//  banked for Phase 2 sponsored posts, where belonging is the point.
//
//  ## Rules that are not ours to bend
//
//  * Attribution is ours to draw — "Ad" here — minimum 15pt in both dimensions, at
//    the top, never painted over an asset. Google renders nothing for us.
//  * AdChoices is injected by the SDK into a corner of the whole ad view and cannot
//    be resized, recoloured, or covered. `adChoicesReserve` is the clear space it
//    lands in; only the chip behind it is ours, and policy requires that chip keep
//    it clearly visible.
//  * Those two must never overlap — hence opposite ends of one strip, which makes
//    it structural rather than a matter of careful positioning.
//  * The CTA must not be interactive. It's registered as a clickable asset view and
//    the SDK's own recogniser records the tap; a real Button swallows it and breaks
//    both click reporting and policy. Everything here is inert by construction.
//

import SwiftUI

struct AdCard: View {
    /// Nil renders the house promo — an unfilled slot must never collapse to a gap.
    let content: NativeAdContent?
    var columnWidth: CGFloat = 0

    @Environment(\.dynamicTypeSize) private var typeSize

    /// Tighter than GridCard's 18. The single cheapest signal that this is app
    /// furniture rather than someone's post.
    static let cornerRadius: CGFloat = 10

    /// Reserved for the SDK-drawn AdChoices overlay.
    static let adChoicesReserve: CGFloat = 22

    /// Fixed before the ad resolves. Layout shift in a masonry grid is the most
    /// hated failure mode there is, and the media's aspect ratio belongs to the
    /// advertiser — so the slot's height is ours to pin, and the media crops into it.
    var cardHeight: CGFloat {
        if typeSize.isAccessibilitySize { return 360 }
        let ideal = columnWidth * 1.62
        return max(250, min(ideal, 320))
    }

    private var mediaHeight: CGFloat {
        guard !typeSize.isAccessibilitySize else { return 150 }
        // 3:2 of the column. Cropped to fill, so whatever ratio arrives still lands
        // in exactly this box.
        return max(0, columnWidth) / 1.5
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            strip
            if let content {
                if content.hasMedia { media }
                text(for: content)
            } else {
                housePromo
            }
        }
        .frame(height: cardHeight, alignment: .top)
        .frame(maxWidth: .infinity)
        .background(surface)
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .stroke(.primary.opacity(0.28), lineWidth: 1.5)
        }
        // The whole card is one element to VoiceOver; its assets aren't independently
        // meaningful, and the SDK owns activation.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - Strip

    /// Attribution leading, AdChoices reserve trailing. Opposite ends of one band,
    /// so the "must not overlap" rule holds by construction.
    private var strip: some View {
        HStack(spacing: 8) {
            Text(content == nil ? "On Board" : "Ad")
                .fontStyle(.caption2)
                .fontWeight(.bold)
                .kerning(0.8)
                .textCase(.uppercase)
                .foregroundStyle(.primary)
                // The 15pt attribution minimum is on the rendered badge, so it's
                // enforced here rather than left to whatever the text measures.
                .frame(minWidth: 15, minHeight: 15, alignment: .leading)

            Spacer(minLength: 0)

            if content != nil {
                // Empty on purpose: the SDK draws the icon into this corner. We
                // only supply the clear space and the chip it sits on.
                Circle()
                    .fill(.background.opacity(0.9))
                    .overlay { Circle().stroke(.primary.opacity(0.2), lineWidth: 0.5) }
                    .frame(width: Self.adChoicesReserve, height: Self.adChoicesReserve)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.primary.opacity(0.07))
    }

    // MARK: - Media

    private var media: some View {
        // Stand-in until the loader supplies a GADMediaView. Neutral rather than
        // decorative — real creative is loud, and a pretty placeholder would flatter
        // this design into looking calmer than it will be in production.
        Rectangle()
            .fill(.primary.opacity(0.08))
            .frame(height: mediaHeight)
            .overlay {
                Image(systemName: "photo")
                    .fontStyle(.title3)
                    .foregroundStyle(.primary.opacity(0.25))
            }
            .clipped()
            .accessibilityHidden(true)
    }

    // MARK: - Text

    private func text(for content: NativeAdContent) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(content.headline)
                .fontStyle(.subheadline)
                .fontWeight(.heavy)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)

            // Conditional assets: rendered only when served, and their absence
            // closes upward rather than changing the card's height.
            if let body = content.body {
                Text(body)
                    .fontStyle(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.tail)
            }

            if let advertiser = content.advertiser {
                Text(advertiser)
                    .fontStyle(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            if let cta = content.callToAction {
                callToAction(cta)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Button-shaped, never a Button. Full width with truncation because the string
    /// is the advertiser's — "Get" and "Download the app today" arrive through the
    /// same field, and an intrinsically-sized pill would either wrap or blow the
    /// fixed height in a ~174pt column.
    private func callToAction(_ title: String) -> some View {
        Text(title)
            .fontStyle(.caption)
            .fontWeight(.bold)
            .lineLimit(1)
            .truncationMode(.tail)
            .foregroundStyle(.background)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(.primary, in: Capsule())
            .allowsHitTesting(false)
    }

    // MARK: - House promo

    /// Unsold inventory becomes subscription marketing rather than a hole in the
    /// grid — the flywheel the roadmap describes, and the reason an unfilled slot
    /// is a normal outcome instead of an error.
    private var housePromo: some View {
        VStack(alignment: .leading, spacing: 6) {
            Spacer(minLength: 0)
            Text("Your board, only your campus.")
                .fontStyle(.subheadline)
                .fontWeight(.heavy)
                .foregroundStyle(.primary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            Text("First Class clears promoted cards off your week.")
                .fontStyle(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            Spacer(minLength: 0)
            Text("See First Class")
                .fontStyle(.caption)
                .fontWeight(.bold)
                .lineLimit(1)
                .foregroundStyle(.background)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(.primary, in: Capsule())
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Surface

    /// Flat and matte where post cards are glass. Another free axis of separation
    /// that costs nothing and survives both colour schemes.
    private var surface: some View {
        Rectangle().fill(.primary.opacity(0.04))
    }

    private var accessibilityLabel: String {
        guard let content else {
            return "On Board. Your board, only your campus. First Class clears promoted cards off your week."
        }
        return [
            "Advertisement.",
            content.headline,
            content.body,
            content.advertiser,
        ]
        .compactMap { $0 }
        .joined(separator: ". ")
    }
}

#Preview("Ad card states") {
    ScrollView {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 16) {
                AdCard(content: MockNativeAdProvider.samples[0], columnWidth: 174)
                AdCard(content: MockNativeAdProvider.samples[2], columnWidth: 174)
                AdCard(content: nil, columnWidth: 174)
            }
            VStack(spacing: 16) {
                AdCard(content: MockNativeAdProvider.samples[1], columnWidth: 174)
                AdCard(content: MockNativeAdProvider.samples[3], columnWidth: 174)
                AdCard(content: MockNativeAdProvider.samples[4], columnWidth: 174)
            }
        }
        .padding(16)
    }
    .background(Color(.systemGroupedBackground))
}
