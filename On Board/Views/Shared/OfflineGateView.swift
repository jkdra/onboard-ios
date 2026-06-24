//
//  OfflineGateView.swift
//  On Board
//
//  Blocks the app when the backend is unreachable until connectivity returns.
//

import SwiftUI

struct OfflineGateView: View {
    
    @Environment(\.dynamicTypeSize) private var typeSize
    
    var onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {

            Text(":(")
                .fontStyle(.largeTitle)
                .fontWeight(.heavy)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 10) {
                Text("On Board ran into a problem and needs to reconnect.")
                    .fontStyle(.title3)
                    .fontWeight(.semibold)
                    .accessibilityLabel("No internet connection")

                Text("We'll get you back on board (heh) as soon as the internet comes back.")
                    .fontStyle(.body)
                    .foregroundStyle(.white.opacity(0.85))
            }
            
            if !typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    Text("If you call a friend, give them this info:")
                    Text("Stop code: NETWORK_UNREACHABLE")
                    
                }
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(.white.opacity(0.8))
            }
            
            Spacer()

            Button(action: onRetry) {
                Label("TRY AGAIN", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.offlineGate)


        }
        .foregroundStyle(.white)
        .persistentSystemOverlays(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { Color.blue.ignoresSafeArea() }
        .environment(\.colorScheme, .light)
        .statusBarHidden()
        .safeAreaPadding()
    }
}

#Preview {
    OfflineGateView(onRetry: {})
}
