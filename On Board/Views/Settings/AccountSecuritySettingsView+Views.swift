//
//  AccountSecuritySettingsView+Views.swift
//  On Board
//
//  Split out of AccountSecuritySettingsView.swift (PostDetailView+Views
//  idiom) — the section and row builders. State plus the
//  refresh/link/unlink logic stay in the core file.
//

import SwiftUI

extension AccountSecuritySettingsView {
    @ViewBuilder
    var traditionalMethodsSection: some View {
        Section {
            if let session = auth.session {
                phoneMethodRow(session: session)
                emailMethodRow(session: session)
                passwordRow(session: session)
            } else if isRefreshing {
                ProgressView("Loading sign-in methods…")
            }
        } header: {
            Text("Sign-In Methods")
                .fontStyle(.subheadline)
        } footer: {
            if auth.session?.hasEmailIdentity == false {
                Text("Keep at least one way to sign in. Link an email to enable password sign-in.")
                    .fontStyle(.footnote)
            } else {
                Text("Keep at least one way to sign in.")
                    .fontStyle(.footnote)
            }
        }
    }

    @ViewBuilder
    private func passwordRow(session: AuthSession) -> some View {
        let canUsePassword = session.hasEmailIdentity
        HStack(spacing: 12) {
            SettingsIconBadge(systemImage: "key.fill")

            VStack(alignment: .leading, spacing: 2) {
                Text("Password")
                    .fontStyle(.body)
                Text(
                    canUsePassword
                        ? (session.hasPassword ? "Sign in with your email and password" : "Not set")
                        : "Link an email first"
                )
                .fontStyle(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if canUsePassword {
                Button(session.hasPassword ? "Change" : "Set") {
                    showPasswordSheet = true
                }
                .fontStyle(.subheadline)
            }
        }
        .opacity(canUsePassword ? 1 : 0.55)
    }

    @ViewBuilder
    var thirdPartySection: some View {
        // Mock (no-Supabase) builds hide the whole section — linking rows
        // against mock stubs read as broken, not as a feature.
        if AppConfiguration.current.isSupabaseConfigured {
            thirdPartySectionContent
        }
    }

    private var thirdPartySectionContent: some View {
        Section {
            if let session = auth.session {
                appleMethodRow(session: session)
                googleMethodRow(session: session)
            }
        } header: {
            Text("Third-Party")
                .fontStyle(.subheadline)
        } footer: {
            Text("To remove Apple or Google, add a phone number, email, or another linked account first.")
                .fontStyle(.footnote)
        }
    }

    private func phoneMethodRow(session: AuthSession) -> some View {
        signInMethodRow(
            provider: .phone,
            detail: session.hasLinked(.phone) ? session.phone : nil,
            isLinked: session.hasLinked(.phone),
            linkAction: { linkSheet = .phone(.link) },
            changeAction: { linkSheet = .phone(.change) }
        )
    }

    private func emailMethodRow(session: AuthSession) -> some View {
        signInMethodRow(
            provider: .email,
            detail: session.hasLinked(.email) ? session.email : nil,
            isLinked: session.hasLinked(.email),
            linkAction: { linkSheet = .email(.link) },
            changeAction: { linkSheet = .email(.change) }
        )
    }

    private func appleMethodRow(session: AuthSession) -> some View {
        let identity = session.linkedIdentities.first { $0.provider == .apple }

        return Group {
            if let identity {
                linkedOAuthRow(identity: identity, session: session)
            } else {
                linkAppleRow
            }
        }
    }

    private func googleMethodRow(session: AuthSession) -> some View {
        let identity = session.linkedIdentities.first { $0.provider == .google }

        return Group {
            if let identity {
                linkedOAuthRow(identity: identity, session: session)
            } else if AppConfiguration.current.isGoogleOAuthAvailable || !AppConfiguration.current.isSupabaseConfigured {
                linkGoogleRow
            } else {
                unavailableOAuthRow(provider: .google)
            }
        }
    }

    private func signInMethodRow(
        provider: AuthProvider,
        detail: String?,
        isLinked: Bool,
        linkAction: @escaping () -> Void,
        changeAction: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            SettingsIconBadge(systemImage: provider.systemImage)

            VStack(alignment: .leading, spacing: 2) {
                Text(provider.securityLabel)
                    .fontStyle(.body)
                if let detail, !detail.isEmpty {
                    Text((provider == .phone ? "+" : "") + detail)
                        .fontStyle(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                } else {
                    Text("Not linked")
                        .fontStyle(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            if !isLinked {
                Button("Link", action: linkAction)
                    .fontStyle(.subheadline)
            } else {
                Button("Change", action: changeAction)
                    .fontStyle(.subheadline)
            }
        }
    }

    private func linkedOAuthRow(identity: LinkedIdentity, session: AuthSession) -> some View {
        HStack(spacing: 12) {
            if identity.provider == .google {
                GoogleIconBadge()
            } else {
                SettingsIconBadge(systemImage: identity.provider.systemImage)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(identity.provider.securityLabel)
                    .fontStyle(.body)
                if !session.canUnlinkIdentity(identity) {
                    Text("Connect another method to unlink")
                        .fontStyle(.caption)
                        .foregroundStyle(.secondary)
                } else if let email = identity.email ?? session.email, !email.isEmpty {
                    Text(email)
                        .fontStyle(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            Spacer(minLength: 8)

            if session.canUnlinkIdentity(identity) {
                Menu {
                    Button("Unlink \(identity.provider.label)", role: .destructive) {
                        identityPendingUnlink = identity
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("Linked")
                        Image(systemName: "chevron.up.chevron.down")
                            .fontStyle(.caption2)
                    }
                    .fontStyle(.subheadline)
                    .foregroundStyle(.secondary)
                }
                .accessibilityLabel("\(identity.provider.label) linked")
                .accessibilityHint("Opens the option to unlink this sign-in method")
            } else {
                Text("Linked")
                    .fontStyle(.subheadline)
                    .foregroundStyle(.tertiary)
                    .accessibilityLabel("\(identity.provider.label) linked. Connect another sign-in method to unlink.")
            }
        }
    }

    private var linkAppleRow: some View {
        oauthLinkRow(
            icon: { SettingsIconBadge(systemImage: AuthProvider.apple.systemImage) },
            label: "Apple",
            isLinking: isLinkingApple,
            action: linkApple
        )
    }

    private var linkGoogleRow: some View {
        oauthLinkRow(
            icon: { GoogleIconBadge() },
            label: "Google",
            isLinking: isLinkingGoogle,
            action: linkGoogle
        )
    }

    private func oauthLinkRow<Icon: View>(
        @ViewBuilder icon: () -> Icon,
        label: String,
        isLinking: Bool,
        action: @escaping () async -> Void
    ) -> some View {
        Button {
            Task { await action() }
        } label: {
            HStack(spacing: 12) {
                icon()
                Text(label)
                    .fontStyle(.body)
                Spacer()
                if isLinking {
                    ProgressView()
                } else {
                    Text("Link")
                        .fontStyle(.subheadline)
                        .foregroundStyle(Color.primary)
                }
            }
        }
        .disabled(isLinking)
    }

    private func unavailableOAuthRow(provider: AuthProvider) -> some View {
        HStack(spacing: 12) {
            if provider == .google {
                GoogleIconBadge()
            } else {
                SettingsIconBadge(systemImage: provider.systemImage)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(provider.securityLabel)
                    .fontStyle(.body)
                Text("Enable Google in your Supabase project to link this account.")
                    .fontStyle(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .opacity(0.55)
    }
}

/// Matches `SettingsIconBadge`'s sizing/corner radius, but for Google's brand
/// asset image rather than an SF Symbol — Google's logo shouldn't be
/// recolored to `.primary`, so it sits on a plain neutral square instead.
private struct GoogleIconBadge: View {
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 28

    var body: some View {
        Image("Google_Favicon_2025")
            .renderingMode(.original)
            .resizable()
            .scaledToFit()
            .frame(width: size * 0.6, height: size * 0.6)
            .frame(width: size, height: size)
            .background {
                RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
                    .fill(Color(.secondarySystemFill))
            }
            .accessibilityHidden(true)
    }
}
