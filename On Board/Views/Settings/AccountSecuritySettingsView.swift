//
//  AccountSecuritySettingsView.swift
//  On Board
//

import SwiftUI

struct AccountSecuritySettingsView: View {
    @Environment(AuthStore.self) private var auth

    var body: some View {
        Form {
            Section {
                if let session = auth.session {
                    LabeledContent {
                        Label(session.provider.securityLabel, systemImage: session.provider.systemImage)
                    } label: {
                        Text("Sign-in method")
                    }

                    if let email = session.email, !email.isEmpty {
                        LabeledContent {
                            Text(email)
                                .textSelection(.enabled)
                        } label: {
                            Text("Email on file")
                        }
                    }
                }
            } header: {
                Text("Sign-in & recovery")
                    .fontStyle(.subheadline)
            } footer: {
                Text("Your sign-in method is managed by your identity provider.")
                    .fontStyle(.footnote)
            }

            Section {
                securityPlaceholder(
                    title: "Passkeys",
                    subtitle: "Sign in without a password",
                    systemImage: "person.badge.key.fill"
                )
                securityPlaceholder(
                    title: "Two-factor authentication",
                    subtitle: "Extra protection for your account",
                    systemImage: "lock.shield.fill"
                )
            } header: {
                Text("Security")
                    .fontStyle(.subheadline)
            } footer: {
                Text("Additional security options are coming soon.")
                    .fontStyle(.footnote)
            }
        }
        .navigationTitle("Security")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func securityPlaceholder(title: String, subtitle: String, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .fontStyle(.body)
                Text(subtitle)
                    .fontStyle(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Text("Soon")
                .fontStyle(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule(style: .continuous).fill(.quaternary))
        }
        .opacity(0.55)
        .accessibilityLabel("\(title), coming soon")
    }
}

#Preview {
    NavigationStack {
        AccountSecuritySettingsView()
    }
    .environment(AuthStore(service: MockAuthService()))
}
