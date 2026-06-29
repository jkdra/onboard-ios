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
    private let spinnerTint: Color

    init(
        _ title: LocalizedStringKey,
        systemImage: String? = nil,
        isLoading: Bool,
        spinnerTint: Color = Color(uiColor: .systemBackground)
    ) {
        self.title = title
        self.systemImage = systemImage
        self.isLoading = isLoading
        self.spinnerTint = spinnerTint
    }

    var body: some View {
        HStack(spacing: 8) {
            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .tint(spinnerTint)
                    .transition(.opacity)
            }

            if let systemImage {
                Label(title, systemImage: systemImage)
            } else {
                Text(title)
            }
        }
        .animation(.snappy(duration: 0.2), value: isLoading)
    }
}
