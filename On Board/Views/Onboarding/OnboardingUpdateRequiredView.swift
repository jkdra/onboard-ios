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
//  Renders the shared UpdateRequiredWall (the OfflineGateView-family blocking
//  wall) with onboarding-specific copy. No back affordance and no way to skip —
//  any escape hatch would drop the user into a flow that cannot complete.
//

import SwiftUI

struct OnboardingUpdateRequiredView: View {
    var body: some View {
        UpdateRequiredWall(
            title: "This version of On Board is too old to get you set up.",
            message: "Your account's setup steps are newer than this build understands. Grab the update and we'll pick up right where you left off."
        )
        .navigationBarBackButtonHidden()
    }
}

#Preview {
    NavigationStack { OnboardingUpdateRequiredView() }
}
