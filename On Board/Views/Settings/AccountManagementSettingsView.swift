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
                    SettingsRowLabel(title: "Request Data Export", systemImage: "doc.text.magnifyingglass")
                }
                .tint(.primary)

                NavigationLink(destination: BlockedUsersSettingsView()) {
                    SettingsRowLabel(title: "Blocked Users", systemImage: "person.crop.circle.fill.badge.xmark")
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
                    SettingsRowLabel(title: "Sign Out", systemImage: "rectangle.portrait.and.arrow.right.fill")
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
                        SettingsRowLabel(title: "Disable Account", systemImage: "person.crop.circle.fill.badge.xmark", tint: .red)
                        Spacer()
                        if isDisabling {
                            ProgressView()
                        }
                    }
                }
                .disabled(isDisabling)

                NavigationLink(destination: DeleteAccountView()) {
                    SettingsRowLabel(title: "Delete Account", systemImage: "trash.fill", tint: .red)
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
        .authFailureAlert(auth, error: $alertError)
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
