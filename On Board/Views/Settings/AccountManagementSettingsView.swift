//
//  AccountManagementSettingsView.swift
//  On Board
//

import SwiftUI

struct AccountManagementSettingsView: View {
    @Environment(AuthStore.self) private var auth

    @State private var showDeleteConfirmation = false
    @State private var showDeleteFinalConfirmation = false
    @State private var isDeleting = false
    @State private var alertError: PresentableAlertError?

    var body: some View {
        Form {
            Section {
                Button {
                    Task { await auth.signOut() }
                } label: {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                }
            } header: {
                Text("Session")
                    .fontStyle(.subheadline)
            }

            Section {
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    HStack {
                        Label("Delete Account", systemImage: "trash")
                        Spacer()
                        if isDeleting {
                            ProgressView()
                        }
                    }
                }
                .disabled(isDeleting)
            } header: {
                Text("Account Management")
                    .fontStyle(.subheadline)
            } footer: {
                Text("Deleting your account permanently removes your profile, posts, and comments. This cannot be undone.")
                    .fontStyle(.footnote)
            }
        }
        .navigationTitle("Account Management")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Delete your account?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Continue", role: .destructive) {
                showDeleteFinalConfirmation = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll be asked to confirm one more time. Your posts and profile will be permanently removed.")
        }
        .confirmationDialog(
            "This permanently deletes your account.",
            isPresented: $showDeleteFinalConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Account", role: .destructive) {
                Task { await deleteAccount() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You won't be able to recover your account or any content you've shared.")
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

    private func deleteAccount() async {
        isDeleting = true
        defer { isDeleting = false }

        await auth.deleteAccount()
    }
}

#Preview {
    NavigationStack {
        AccountManagementSettingsView()
    }
    .environment(AuthStore(service: MockAuthService()))
}
