//
//  OfflineGateView.swift
//  On Board
//
//  Blocks the app when the backend is unreachable until connectivity returns.
//

import SwiftUI

struct OfflineGateView: View {
    @Environment(\.colorScheme) private var scheme
    var onRetry: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "wifi.slash")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            VStack(spacing: 10) {
                Text("No connection")
                    .fontStyle(.largeTitle)
                    .fontWeight(.heavy)

                Text("On Board needs internet to sign in, finish setup, and load your board. Check your connection and try again.")
                    .fontStyle(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }

            Button(action: onRetry) {
                Label("Try again", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.boardPrimary)
            .padding(.horizontal, 24)

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            LinearGradient(
                colors: [
                    Color.gray.opacity(scheme == .light ? 0.22 : 0.18),
                    Color(.systemBackground)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }
}

#Preview {
    OfflineGateView(onRetry: {})
}
