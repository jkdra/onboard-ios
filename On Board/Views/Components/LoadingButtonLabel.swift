//
//  LoadingButtonLabel.swift
//  On Board
//
//  A button label that shows a small progress indicator to the LEFT of its
//  title while a request is in flight, instead of swapping the whole screen for
//  a loading view. Pair it with `.disabled(isLoading)` on the page (or at least
//  the button) so the control greys out while the spinner shows — the standard
//  "in-flight CTA" affordance used across the app.
//
//  Spinner colour defaults to `systemBackground`, which matches the filled
//  `.boardPrimary` style's label in both light and dark mode. For `.boardSecondary`
//  (or any non-filled button) pass `spinnerTint: .primary`.
//

import SwiftUI

struct LoadingButtonLabel: View {
    private let title: LocalizedStringKey
    private let systemImage: String?
    private let isLoading: Bool
    private let isActive: Bool
    private let spinnerTint: Color

    init(
        _ title: LocalizedStringKey,
        systemImage: String? = nil,
        isLoading: Bool,
        isActive: Bool = true,
        spinnerTint: Color = Color(uiColor: .systemBackground)
    ) {
        self.title = title
        self.systemImage = systemImage
        self.isLoading = isLoading
        self.isActive = isActive
        self.spinnerTint = spinnerTint
    }

    private var isRightAligned: Bool {
        systemImage == "arrow.forward"
    }

    var body: some View {
        HStack(spacing: 8) {
            if !isRightAligned {
                iconOrSpinner
            }
            
            Text(title)
            
            if isRightAligned {
                iconOrSpinner
            }
        }
        .animation(.snappy(duration: 0.3), value: isLoading)
        .animation(.snappy(duration: 0.3), value: isActive)
    }

    @ViewBuilder
    private var iconOrSpinner: some View {
        if isLoading {
            ProgressView()
                .controlSize(.small)
                .tint(spinnerTint)
                .transition(.scale.combined(with: .opacity))
        } else if isActive, let systemImage {
            Image(systemName: systemImage)
                .transition(.scale.combined(with: .opacity))
        }
    }
}
