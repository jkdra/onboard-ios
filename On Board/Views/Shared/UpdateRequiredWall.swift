//
//  UpdateRequiredWall.swift
//  On Board
//
//  The blocking "this build is too old" wall, in the same visual family as
//  OfflineGateView — the app's established full-screen system-wall look
//  (flat blue, heavy text glyph, white type, monospaced stop code, angular
//  outline button). Two situations show it:
//
//  * the remote version gate (`min_supported_version`), as a root BRANCH in
//    RootView — never a presentation; a branch can't silently fail to appear
//    the way the original fullScreenCover did, and
//  * `OnboardingStep.unrecognized`, when the server's onboarding flow is newer
//    than this build understands (OnboardingUpdateRequiredView wraps this).
//
//  Deliberately no dismiss affordance of any kind: the wall only appears when
//  no local behavior is correct, so every way out leads through the App Store.
//

import SwiftUI

struct UpdateRequiredWall: View {
    var title = "This version of On Board can't keep up."
    var message = "The board has moved ahead of this build. Grab the update and we'll get you right back on."

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {

            // ":O" to OfflineGateView's ":(" — surprised, not sad. Nothing is
            // broken; the board just moved on without this build.
            Text(":O")
                .fontStyle(.largeTitle)
                .fontWeight(.heavy)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .fontStyle(.title3)
                    .fontWeight(.semibold)
                    // A heading trait, NOT a replacement label — an override
                    // here silenced the actual title (including the custom one
                    // OnboardingUpdateRequiredView passes) for VoiceOver users.
                    .accessibilityAddTraits(.isHeader)

                Text(message)
                    .fontStyle(.body)
                    .foregroundStyle(.white.opacity(0.85))
            }

            if !typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    Text("If you call a friend, give them this info:")
                    Text("Stop code: UPDATE_REQUIRED")
                }
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(.white.opacity(0.8))
            }

            Spacer()

            Button {
                openURL(AppLinks.appStoreURL)
            } label: {
                Label("UPDATE ON BOARD", systemImage: "arrow.down.circle")
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
    UpdateRequiredWall()
}
