//
//  OnboardingBirthdayStepView.swift
//  On Board
//

import SwiftUI

struct OnboardingBirthdayStepView: View {
    @Environment(OnboardingStore.self) private var onboarding

    @State private var birthday: Date?
    @State private var showBirthday: Bool = false
    @State private var showAgeConfirm = false

    private var minAgeDate: Date {
        Calendar.current.date(byAdding: .year, value: -16, to: Date()) ?? Date()
    }

    private var canContinue: Bool {
        birthday != nil && !onboarding.isSubmitting
    }

    private var age: Int {
        guard let birthday else { return 0 }
        return Calendar.current.dateComponents([.year], from: birthday, to: Date()).year ?? 0
    }
    
    var body: some View {
        ScrollView {
            OnboardingProgressBar(step: 1, totalSteps: 5)
                .safeAreaPadding(.horizontal)
            VStack(alignment: .leading, spacing: 24) {

                Text("You must be at least 16 years old to use On Board. We use this to verify your age.")
                    .fontStyle(.subheadline)
                    .foregroundStyle(.secondary)

                BirthdayWheelPicker(date: $birthday, isEnabled: !onboarding.isSubmitting, maximumDate: minAgeDate)

                Toggle("Show month and day on profile", isOn: $showBirthday)
                    .fontStyle(.body)
                    .tint(.primary)

                Button {
                    // Birthday is locked after this, so confirm the age first.
                    showAgeConfirm = true
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
        .alert("You're \(age) years old?", isPresented: $showAgeConfirm) {
            Button("Go Back", role: .cancel) {}
            Button("Yep, looks good.") {
                guard let birthday else { return }
                Task {
                    await onboarding.submitBirthday(birthday: birthday, showBirthday: showBirthday)
                }
            }
        } message: {
            Text("Double-check your date of birth — you won't be able to change it later.")
        }
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
