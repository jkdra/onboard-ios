//
//  OnboardingContentPreferencesStepView.swift
//  On Board
//

import SwiftUI

struct OnboardingContentPreferencesStepView: View {
    @AppStorage("profanityEnabled") private var profanityEnabled = false
    @AppStorage("hasCompletedProfanityStep") private var hasCompletedProfanityStep = false

    var body: some View {
        ScrollView {
            OnboardingProgressBar(step: 4, totalSteps: 6)
                .safeAreaPadding(.horizontal)
            VStack(alignment: .leading, spacing: 24) {
                

                VStack(alignment: .leading, spacing: 8) {
                    Text("Some weekly prompts and official messaging may have a... more raw version. Enable this if you want to see it.")
                        .fontStyle(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Toggle(isOn: $profanityEnabled) {
                    Text("Allow profanity")
                        .fontStyle(.body)
                }
                .tint(.primary)

                Label(
                    "This only affects prompts and messages from us — it doesn't change what other people post, comment, or share.",
                    systemImage: "info.circle.fill"
                )
                .fontStyle(.footnote)
                .foregroundStyle(.secondary)

                Button {
                    hasCompletedProfanityStep = true
                } label: {
                    LoadingButtonLabel("Continue", systemImage: "arrow.forward", isLoading: false)
                }
                .buttonStyle(.boardPrimary)
            }
            .safeAreaPadding(.horizontal)
        }
        .navigationTitle("Profanity")
    }
}

#Preview {
    NavigationStack {
        OnboardingContentPreferencesStepView()
    }
}
