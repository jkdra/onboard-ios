//
//  InstitutionSettingsView.swift
//  On Board
//
//  Campus/institution settings: shows the verified (or not-yet-verified) campus
//  email + school, and lets the user view/edit their expected graduation month.
//

import SwiftUI

struct InstitutionSettingsView: View {
    @Environment(OnboardingStore.self) private var onboarding
    @State private var showGraduationEditor = false

    private var status: OnboardingStatus? { onboarding.status }

    var body: some View {
        List {
            Section {
                LabeledContent {
                    if let email = status?.verifiedSchoolEmail {
                        Text(email).foregroundStyle(.secondary)
                    } else {
                        Label("Not verified", systemImage: "exclamationmark.circle")
                            .foregroundStyle(.secondary)
                    }
                } label: {
                    Text("Campus email").fontStyle(.body)
                }

                if let school = status?.schoolName {
                    LabeledContent {
                        Text(school).foregroundStyle(.secondary)
                    } label: {
                        Text("School").fontStyle(.body)
                    }
                }
            } header: {
                Text("Campus").fontStyle(.subheadline)
            } footer: {
                if status?.verifiedSchoolEmail == nil {
                    Text("Verify your campus email during onboarding to join your board.")
                        .fontStyle(.footnote)
                }
            }

            Section {
                Button {
                    showGraduationEditor = true
                } label: {
                    LabeledContent {
                        Text(GraduationMonth.display(status?.expectedGraduation) ?? "Set")
                            .foregroundStyle(.secondary)
                    } label: {
                        Text("Expected graduation").fontStyle(.body)
                    }
                    .contentShape(.rect)
                }
                .foregroundStyle(.primary)
            } header: {
                Text("Graduation").fontStyle(.subheadline)
            } footer: {
                Text("We use this to keep your board with you when you become an alum. Month and year only.")
                    .fontStyle(.footnote)
            }
        }
        .navigationTitle("Institution Settings")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showGraduationEditor) {
            GraduationEditorSheet(current: status?.expectedGraduation)
        }
    }
}

/// Month + year picker sheet, used to set or edit expected graduation.
struct GraduationEditorSheet: View {
    let current: String?

    @Environment(OnboardingStore.self) private var onboarding
    @Environment(\.dismiss) private var dismiss

    @State private var month: Int
    @State private var year: Int

    private let monthNames: [String] = DateFormatter().monthSymbols

    init(current: String?) {
        self.current = current
        let parsed = GraduationMonth.parse(current)
        _month = State(initialValue: parsed?.month ?? 5)
        _year = State(initialValue: parsed?.year ?? Calendar.current.component(.year, from: Date()) + 1)
    }

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
        NavigationStack {
            VStack {
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
            }
            .disabled(onboarding.isSubmitting)
            .navigationTitle("Expected graduation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Label("Cancel", systemImage: "xmark")
                    }
                    .disabled(onboarding.isSubmitting)
                }
                // Confirm lives in the top-trailing slot as a prominent checkmark
                // — the `.boardPrimary` bottom button rendered grayed (a SwiftUI
                // tint quirk on that style inside a sheet), so this reads as the
                // clear, always-tinted primary action instead.
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        guard let date = selectedDate else { return }
                        Task {
                            let ok = await onboarding.submitGraduation(date)
                            if ok { dismiss() }
                        }
                    } label: {
                        if onboarding.isSubmitting {
                            ProgressView()
                        } else {
                            Label("Save", systemImage: "checkmark")
                                .labelStyle(.iconOnly)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(onboarding.isSubmitting)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
