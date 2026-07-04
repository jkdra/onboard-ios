//
//  AccountManagementSettingsView.swift
//  On Board
//

import SwiftUI

struct AccountManagementSettingsView: View {
    @Environment(AuthStore.self) private var auth

    @State private var showDisableConfirmation = false
    @State private var isDisabling = false
    @State private var alertError: PresentableAlertError?
    @State private var showExportConfirmation = false

    var body: some View {
        Form {
            Section {
                Button {
                    showExportConfirmation = true
                } label: {
                    Label("Request Data Export", systemImage: "doc.text.magnifyingglass")
                        .fontStyle(.body)
                }
                .tint(.primary)
                
                Button {
                    // Placeholder for blocked users functionality
                } label: {
                    Label("Blocked Users", systemImage: "person.crop.circle.fill.badge.xmark")
                        .fontStyle(.body)
                }
                .tint(.primary)
            } header: {
                Text("Data & Privacy")
                    .fontStyle(.subheadline)
            } footer: {
                Text("Requesting a data export will send an archive of your profile and posts to your email.")
                    .fontStyle(.footnote)
            }

            Section {
                Button {
                    Task { await auth.signOut() }
                } label: {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right.fill")
                        .fontStyle(.body)
                }
                .tint(.primary)
            } header: {
                Text("Session")
                    .fontStyle(.subheadline)
            }

            Section {
                Button(role: .destructive) {
                    showDisableConfirmation = true
                } label: {
                    HStack {
                        Label("Disable Account", systemImage: "person.crop.circle.fill.badge.xmark")
                            .fontStyle(.body)
                        Spacer()
                        if isDisabling {
                            ProgressView()
                        }
                    }
                }
                .disabled(isDisabling)
                
                NavigationLink(destination: DeleteAccountView()) {
                    Label("Delete Account", systemImage: "trash.fill")
                        .fontStyle(.body)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("Danger Zone")
                    .fontStyle(.subheadline)
            } footer: {
                Text("Disabling your account hides your profile and posts until you sign in again. Deleting your account permanently removes all your data.")
                    .fontStyle(.footnote)
            }
        }
        .navigationTitle("Account Management")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Disable your account?",
            isPresented: $showDisableConfirmation,
            titleVisibility: .visible
        ) {
            Button("Disable Account", role: .destructive) {
                Task { await disableAccount() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your profile and posts will be hidden from everyone. You can reactivate your account at any time by signing back in.")
        }
        .alert("Data Export Requested", isPresented: $showExportConfirmation) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("We'll send an email with a link to download your data within a few minutes.")
        }
        .presentableErrorAlert(error: $alertError) {
            if case .failed = auth.state {
                auth.cancelSignIn()
            }
        }
        .onChange(of: authFailureMessage) { _, message in
            guard let message else { return }
            alertError = PresentableAlertError(message: message)
        }
    }

    private var authFailureMessage: String? {
        if case .failed(let message) = auth.state { message }
        else { nil }
    }

    private func disableAccount() async {
        isDisabling = true
        defer { isDisabling = false }
        
        // Disabling logic will go here
        await auth.signOut() // Temporarily just sign out
    }
}

#Preview {
    NavigationStack {
        AccountManagementSettingsView()
    }
    .environment(AuthStore(service: MockAuthService()))
}
