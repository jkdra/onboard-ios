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
//  A dismissed card stays dismissed for that version — nagging on every
//  foreground trains people to dismiss without reading, which is exactly the
//  reflex you don't want the day the hard wall appears for real.
//

import SwiftUI

struct UpdateAvailableModifier: ViewModifier {
    let requirement: UpdateRequirement

    @Environment(\.openURL) private var openURL
    @AppStorage("update.dismissedForVersion") private var dismissedForVersion = ""
    @State private var showingCard = false

    func body(content: Content) -> some View {
        content
            .onChange(of: requirement, initial: true) { _, requirement in
                showingCard = requirement == .recommended
                    && dismissedForVersion != AppVersion.current
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
        dismissedForVersion = AppVersion.current
        showingCard = false
    }

    private var updateCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                BrandLogo(size: 34)
                Text("A new On Board is out.")
                    .fontStyle(.title3)
                Spacer(minLength: 0)
            }

            Text("Fixes, polish, the works — it only takes a second to grab.")
                .fontStyle(.footnote)
                .foregroundStyle(.secondary)

            HStack(spacing: 14) {
                Button("Not now", action: dismiss)
                    .fontStyle(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)

                Button {
                    openURL(AppLinks.appStoreURL)
                    dismiss()
                } label: {
                    Label("Update", systemImage: "arrow.down.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.boardPrimary)
            }
            .padding(.top, 4)
        }
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.regularMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(.primary.opacity(0.10), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.18), radius: 18, y: 6)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Update available")
    }
}

extension View {
    func updatePrompt(_ requirement: UpdateRequirement) -> some View {
        modifier(UpdateAvailableModifier(requirement: requirement))
    }
}
