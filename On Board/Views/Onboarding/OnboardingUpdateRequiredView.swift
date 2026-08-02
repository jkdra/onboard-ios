//
//  OnboardingUpdateRequiredView.swift
//  On Board
//
//  Terminal screen for `OnboardingStep.unrecognized` — the server asked this
//  build to show an onboarding step it has never heard of, which means the
//  client is older than the account's onboarding flow. There is no correct
//  local behavior: admitting the user would let someone skip a step, and
//  guessing a step could trap them in a loop.
//
//  Deliberately has no back affordance and no way to skip — any escape hatch
//  would drop the user into a flow that cannot complete.
//

import SwiftUI

struct OnboardingUpdateRequiredView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "arrow.down.circle")
                .font(.system(size: 52))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text("Time for an update")
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)

            Text("This version of On Board is too old to finish setting up your account. Update to the latest version to continue.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()

            Button {
                openURL(AppLinks.appStoreURL)
            } label: {
                Text("Update On Board")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .navigationBarBackButtonHidden()
        .interactiveDismissDisabled()
    }
}

#Preview {
    NavigationStack { OnboardingUpdateRequiredView() }
}
