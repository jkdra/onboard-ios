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
//  Also hosts the profanity preference (2026-08-07): the old standalone
//  `.contentPreferences` step was a full push for one toggle whose default
//  nearly everyone keeps. Two light single-choice screens merged into one
//  "last details" stop — onboarding went from 7 pushes to 6, and the profile
//  step now flows straight into school verification.
//

import SwiftUI

struct OnboardingGraduationStepView: View {
    @Environment(OnboardingStore.self) private var onboarding
    @AppStorage("profanityEnabled") private var profanityEnabled = false

    @State private var month = 5   // May
    @State private var year = Calendar.current.component(.year, from: Date()) + 1

    // Calendar.current.monthSymbols avoids constructing a DateFormatter just
    // to read a fixed symbol list — cheap either way, but this runs on every
    // re-init of the view struct (i.e. every parent re-render), not once.
    private let monthNames: [String] = Calendar.current.monthSymbols

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
            OnboardingProgressBar(step: 5, totalSteps: 6)
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

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    Text("Some weekly prompts and official messaging may have a... more raw version. Enable this if you want to see it.")
                        .fontStyle(.subheadline)
                        .foregroundStyle(.secondary)

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
                }

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
        .navigationTitle("Last details")
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
