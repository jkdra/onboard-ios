//
//  AccountManagementSettingsView.swift
//  On Board
//

import SwiftUI

struct AccountManagementSettingsView: View {
    @Environment(AuthStore.self) private var auth

    @State private var alertError: PresentableAlertError?

    var body: some View {
        Form {
            Section {
                Button {
                    Task { await auth.signOut() }
                } label: {
                    SettingsRowLabel(title: "Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                }
                .tint(.primary)
            } header: {
                Text("Session")
                    .fontStyle(.subheadline)
            }

            Section {
                NavigationLink(destination: DeleteAccountView()) {
                    SettingsRowLabel(title: "Delete Account", systemImage: "trash.fill", tint: .red)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("Danger Zone")
                    .fontStyle(.subheadline)
            } footer: {
                Text("Deleting your account permanently removes all your data.")
                    .fontStyle(.footnote)
            }
        }
        .navigationTitle("Account Management")
        .navigationBarTitleDisplayMode(.inline)
        .authFailureAlert(auth, error: $alertError)
    }
}

#Preview {
    NavigationStack {
        AccountManagementSettingsView()
    }
    .environment(AuthStore(service: MockAuthService()))
}
