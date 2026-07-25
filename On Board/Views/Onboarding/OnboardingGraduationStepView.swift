//
//  OnboardingGraduationStepView.swift
//  On Board
//
//  Client-inserted step shown right after school verification: capture the
//  user's expected graduation month + year. It's load-bearing for a future
//  alumni transition and can't be re-collected once a .edu is deactivated, so
//  we grab it now while the account is a verified student. Month + year only —
//  a grace period makes the exact day pointless. Editable later in Settings.
//

import SwiftUI

struct OnboardingGraduationStepView: View {
    @Environment(OnboardingStore.self) private var onboarding

    @State private var month = 5   // May
    @State private var year = Calendar.current.component(.year, from: Date()) + 1

    private let monthNames: [String] = DateFormatter().monthSymbols

    private var years: [Int] {
        let current = Calendar.current.component(.year, from: Date())
        return Array(current...(current + 8))
    }

    private var selectedDate: Date? {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = 1
        return Calendar.current.date(from: comps)
    }

    var body: some View {
        ScrollView {
            OnboardingProgressBar(step: 6, totalSteps: 7)
                .safeAreaPadding(.horizontal)

            VStack(alignment: .leading, spacing: 24) {
                Text("When do you expect to graduate? This lets your board follow you when you become an alum. You can change it anytime in Settings.")
                    .fontStyle(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 0) {
                    Picker("Month", selection: $month) {
                        ForEach(1...12, id: \.self) { m in
                            Text(monthNames[m - 1]).tag(m)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)

                    Picker("Year", selection: $year) {
                        ForEach(years, id: \.self) { y in
                            Text(String(y)).tag(y)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)
                }
                .disabled(onboarding.isSubmitting)

                Button {
                    guard let date = selectedDate else { return }
                    Task { await onboarding.submitGraduation(date) }
                } label: {
                    LoadingButtonLabel("Continue", systemImage: "arrow.forward", isLoading: onboarding.isSubmitting, isActive: true)
                }
                .buttonStyle(.boardPrimary)
                .disabled(onboarding.isSubmitting)
            }
            .safeAreaPadding(.horizontal)
        }
        .disabled(onboarding.isSubmitting)
        .navigationTitle("Graduation")
    }
}

#Preview {
    NavigationStack {
        OnboardingGraduationStepView()
    }
    .environment(OnboardingStore(
        service: MockOnboardingService(),
        auth: AuthStore(service: MockAuthService()),
        network: NetworkMonitor()
    ))
}
