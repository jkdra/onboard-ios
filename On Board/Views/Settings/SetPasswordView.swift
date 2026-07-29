//
//  SetPasswordView.swift
//  On Board
//
//  Set or change the account password. Requires a linked email identity —
//  password sign-in is email + password. Presented as a sheet from
//  AccountSecuritySettingsView.
//

import SwiftUI

struct SetPasswordView: View {
    /// Called after the password is saved successfully.
    var onSaved: (() -> Void)?

    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isSaving = false
    @State private var alertError: PresentableAlertError?
    @FocusState private var focusedField: Field?

    private enum Field { case password, confirm }

    private let minimumLength = 8

    private var isChanging: Bool {
        auth.session?.hasPassword == true
    }

    private var passwordsMatch: Bool {
        !confirmPassword.isEmpty && password == confirmPassword
    }

    private var isValid: Bool {
        password.count >= minimumLength && passwordsMatch
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("New password", text: $password)
                        .textContentType(.newPassword)
                        .focused($focusedField, equals: .password)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .confirm }
                    SecureField("Confirm password", text: $confirmPassword)
                        .textContentType(.newPassword)
                        .focused($focusedField, equals: .confirm)
                        .submitLabel(.done)
                        .onSubmit { if isValid { Task { await save() } } }
                } header: {
                    Text(isChanging ? "New Password" : "Create a Password")
                        .fontStyle(.subheadline)
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        if !password.isEmpty, password.count < minimumLength {
                            Text("At least \(minimumLength) characters.")
                                .foregroundStyle(.orange)
                        } else if !confirmPassword.isEmpty, !passwordsMatch {
                            Text("Passwords don't match yet.")
                                .foregroundStyle(.orange)
                        } else {
                            Text("Use at least \(minimumLength) characters. You'll sign in with your email and this password.")
                        }
                    }
                    .fontStyle(.footnote)
                }

                Section {
                    Button {
                        Task { await save() }
                    } label: {
                        LoadingButtonLabel(
                            isChanging ? "Change Password" : "Set Password",
                            systemImage: "key.fill",
                            isLoading: isSaving
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.boardPrimary)
                    .tint(.primary)
                    .disabled(!isValid || isSaving)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
            }
            .navigationTitle(isChanging ? "Change Password" : "Set Password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    // See NewPostView's Cancel button for why the keyboard is
                    // resigned before dismiss() — avoids racing the sheet's
                    // own dismiss transition against the keyboard's hide
                    // animation, which can leave a stale safe-area inset on
                    // whatever screen is shown next.
                    Button {
                        KeyboardDismisser.dismiss()
                        dismiss()
                    } label: { Label("Cancel", systemImage: "xmark").fontWeight(.semibold) }
                        .disabled(isSaving)
                }
            }
            .interactiveDismissDisabled(isSaving)
            .onAppear { focusedField = .password }
            .presentableErrorAlert(error: $alertError)
        }
        .presentationDetents([.medium, .large])
    }

    private func save() async {
        guard isValid else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await auth.setPassword(password)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            KeyboardDismisser.dismiss()
            dismiss()
            onSaved?()
        } catch {
            alertError = PresentableAlertError.from(error)
        }
    }
}

#Preview {
    SetPasswordView()
        .environment(AuthStore(service: MockAuthService()))
}
