//
//  OnboardingBirthdayStepView.swift
//  On Board
//

import SwiftUI

struct OnboardingBirthdayStepView: View {
    @Environment(OnboardingStore.self) private var onboarding

    @State private var birthday: Date?
    @State private var showBirthday: Bool = false

    private var minAgeDate: Date {
        Calendar.current.date(byAdding: .year, value: -16, to: Date()) ?? Date()
    }

    private var canContinue: Bool {
        birthday != nil && !onboarding.isSubmitting
    }
    
    var body: some View {
        ScrollView {
            OnboardingProgressBar(step: 1, totalSteps: 6)
                .safeAreaPadding(.horizontal)
            VStack(alignment: .leading, spacing: 24) {

                Text("You must be at least 16 years old to use On Board. We use this to verify your age.")
                    .fontStyle(.subheadline)
                    .foregroundStyle(.secondary)

                BirthdayGraphicalPicker(date: $birthday, isEnabled: !onboarding.isSubmitting, maximumDate: minAgeDate)

                Toggle("Show month and day on profile", isOn: $showBirthday)
                    .fontStyle(.body)
                    .tint(.primary)

                Button {
                    guard let birthday else { return }
                    Task {
                        await onboarding.submitBirthday(birthday: birthday, showBirthday: showBirthday)
                    }
                } label: {
                    LoadingButtonLabel("Continue", systemImage: "arrow.forward", isLoading: onboarding.isSubmitting, isActive: canContinue)
                }
                .buttonStyle(.boardPrimary)
                .disabled(!canContinue)
            }
            .safeAreaPadding(.horizontal)
        }
        .disabled(onboarding.isSubmitting)
        .navigationTitle("Birthday")

    }
}

#Preview {
    NavigationStack {
        OnboardingBirthdayStepView()
    }
    .environment(OnboardingStore(
        service: MockOnboardingService(),
        auth: AuthStore(service: MockAuthService()),
        network: NetworkMonitor()
    ))
}
