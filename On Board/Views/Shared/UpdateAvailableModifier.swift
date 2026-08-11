//
//  UpdateAvailableModifier.swift
//  On Board
//
//  Surfaces the SOFT half of the version gate: `.recommended` slides a
//  dismissible card up from the bottom. The blocking `.required` state is
//  deliberately NOT handled here — UpdateRequiredWall is a root *branch* in
//  RootView (exactly like OfflineGateView), never a presentation.
//
//  This is an in-tree overlay, not a `.sheet`, and that is load-bearing: three
//  attempts at presenting this through the presentation system failed silently
//  in three different ways (a fullScreenCover losing to RootView's welcome
//  cover on the same node; background-hosted presenters driven during the
//  bootstrap tree swap; and finally the ArchiveTip's popover already holding
//  the presentation context when the sheet asked for it). An overlay has no
//  presentation context to lose — it composites over the feed, coexists with
//  tips, covers, and popovers, and leaves the board usable behind it, which is
//  the right posture for a nudge anyway.
//
//  A dismissed card stays dismissed for that OFFER — the key stores the
//  recommended_version string the user declined, not the running build, so
//  "Not now" against 1.1.2 stays quiet until the server recommends something
//  NEWER (1.1.3 re-prompts; re-seeding 1.1.2 doesn't). Nagging on every
//  foreground trains people to dismiss without reading, which is exactly the
//  reflex you don't want the day the hard wall appears for real.
//
//  The card's corner radius is *derived*, not a constant: concentric corners
//  require outer radius = inner radius + the gap between them, so it is the
//  buttons' measured capsule radius plus `cardPadding`. Hardcoding it would
//  drift the moment Dynamic Type changed the button height.
//

import SwiftUI

struct UpdateAvailableModifier: ViewModifier {
    let requirement: UpdateRequirement
    /// The `recommended_version` string this card is offering. Persisted on
    /// dismiss so the same offer stays dismissed while a newer one re-prompts
    /// — storing `AppVersion.current` here (the original design) silenced
    /// every future recommendation for the life of the running build.
    let offeredVersion: String?

    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var typeSize
    @AppStorage("update.dismissedForVersion") private var dismissedForVersion = ""
    @State private var showingCard = false
    @State private var buttonHeight: CGFloat = 0

    @ScaledMetric(relativeTo: .title2) private var logoSize: CGFloat = 34

    /// Gap between the buttons and the card edge — also the term that keeps
    /// the card's corners concentric with the capsule buttons.
    private static let cardPadding: CGFloat = 18

    /// Concentric outer radius: the capsules' own radius (half their measured
    /// height, so it tracks Dynamic Type) plus the padding between them and
    /// the card edge. The fallback only paints the first frame, before the
    /// buttons have reported a height.
    private var cardCornerRadius: CGFloat {
        buttonHeight > 0 ? buttonHeight / 2 + Self.cardPadding : 43
    }

    func body(content: Content) -> some View {
        content
            .onChange(of: requirement, initial: true) { _, requirement in
                guard requirement == .recommended, let offeredVersion else {
                    showingCard = false
                    return
                }
                showingCard = dismissedForVersion != offeredVersion
            }
            .overlay(alignment: .bottom) {
                if showingCard {
                    updateCard
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.45), value: showingCard)
    }

    private func dismiss() {
        dismissedForVersion = offeredVersion ?? ""
        showingCard = false
    }

    private var updateCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            // Dropped at accessibility sizes, same call UpdateRequiredWall
            // makes with its stop code: four wrapped lines of pure flavor push
            // the buttons off a small screen, and the title plus a labelled
            // Update button already say everything load-bearing.
            if !typeSize.isAccessibilitySize {
                Text("Fixes, polish, the works — it only takes a second to grab.")
                    .fontStyle(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            actions
                .padding(.top, 4)
        }
        .padding(Self.cardPadding)
        .background {
            let shape = RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
            shape
                .fill(.regularMaterial)
                .overlay { shape.strokeBorder(.primary.opacity(0.10), lineWidth: 1) }
                .shadow(color: .black.opacity(0.18), radius: 18, y: 6)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Update available")
    }

    /// The mark sits beside the title normally, above it at accessibility
    /// sizes — a 34pt-scaled logo plus wrapped title leaves the row no usable
    /// width for text.
    @ViewBuilder
    private var header: some View {
        // Scales with type, but capped: unbounded, AX5 takes it past 80pt and
        // the mark alone costs more vertical space than both buttons.
        let logo = BrandLogo(size: min(logoSize, 52))
        let title = Text("A new On Board is out.")
            .fontStyle(.title3)
            .fixedSize(horizontal: false, vertical: true)

        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                logo
                title
            }
        } else {
            HStack(spacing: 12) {
                logo
                title
                Spacer(minLength: 0)
            }
        }
    }

    /// Side-by-side normally; stacked at accessibility sizes, where two
    /// half-width capsules would wrap their labels to three lines each.
    /// Update leads when stacked — vertical order carries the emphasis that
    /// filled-vs-outline carries in the row.
    @ViewBuilder
    private var actions: some View {
        let notNow = Button(action: dismiss) {
            Text("Not now")
                .buttonLabelFit()
        }
        .buttonStyle(.boardSecondary)

        let update = Button {
            openURL(AppLinks.appStoreURL)
            dismiss()
        } label: {
            Label("Update", systemImage: "arrow.down.circle")
                .buttonLabelFit()
        }
        .buttonStyle(.boardPrimary)
        // Measured on one button, not the row: stacked, the row is two
        // capsules tall and would over-round the card. Both capsules are the
        // same height in either layout, so either one is representative.
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { buttonHeight = $0 }

        if typeSize.isAccessibilitySize {
            VStack(spacing: 10) {
                update
                notNow
            }
        } else {
            HStack(spacing: 12) {
                notNow
                update
            }
        }
    }
}

extension View {
    func updatePrompt(_ requirement: UpdateRequirement, offeredVersion: String?) -> some View {
        modifier(UpdateAvailableModifier(requirement: requirement, offeredVersion: offeredVersion))
    }
}

private extension View {
    /// Fills its half of the row and shrinks rather than wraps. Without the
    /// line limit, "Update" broke to "Updat / e" at xxxLarge — which also made
    /// the two capsules different heights, so the card's derived corner radius
    /// no longer matched the button it was measured from.
    func buttonLabelFit() -> some View {
        lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(maxWidth: .infinity)
    }
}
