//
//  AccountSecuritySettingsView.swift
//  On Board
//

import AuthenticationServices
import SwiftUI

struct AccountSecuritySettingsView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.colorScheme) private var scheme

    @State private var isRefreshing = false
    @State private var isLinkingApple = false
    @State private var isLinkingGoogle = false
    @State private var identityPendingUnlink: LinkedIdentity?
    @State private var showUnlinkBlockedAlert = false
    @State private var showAddMethodBeforeUnlink = false
    @State private var linkSheet: LinkSheet?
    @State private var alertError: PresentableAlertError?

    private enum LinkSheet: Identifiable {
        case phone
        case email

        var id: String {
            switch self {
            case .phone: "phone"
            case .email: "email"
            }
        }
    }

    var body: some View {
        Form {
            signInMethodsSection

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
        .task {
            await refreshMethods()
        }
        .refreshable {
            await refreshMethods()
        }
        .sheet(item: $linkSheet) { sheet in
            LinkSignInMethodView(mode: sheet == .phone ? .phone : .email) {
                Task { await refreshMethods() }
            }
        }
        .confirmationDialog(
            "Unlink \(identityPendingUnlink?.provider.label ?? "account")?",
            isPresented: Binding(
                get: { identityPendingUnlink != nil },
                set: { if !$0 { identityPendingUnlink = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Unlink", role: .destructive) {
                guard let identity = identityPendingUnlink else { return }
                Task { await unlink(identity) }
            }
            Button("Cancel", role: .cancel) {
                identityPendingUnlink = nil
            }
        } message: {
            Text("You won't be able to sign in with this method unless you link it again.")
        }
        .alert(
            "Add another sign-in method first",
            isPresented: $showAddMethodBeforeUnlink
        ) {
            Button("Add phone") { linkSheet = .phone }
            Button("Add email") { linkSheet = .email }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Before removing your last sign-in method, add a phone number, email, or link another account. You can also delete your account from Account Management.")
        }
        .presentableErrorAlert(error: $alertError)
    }

    @ViewBuilder
    private var signInMethodsSection: some View {
        Section {
            if let session = auth.session {
                phoneMethodRow(session: session)
                emailMethodRow(session: session)
                appleMethodRow(session: session)
                googleMethodRow(session: session)
            } else if isRefreshing {
                ProgressView("Loading sign-in methods…")
            }
        } header: {
            Text("Sign-in methods")
                .fontStyle(.subheadline)
        } footer: {
            Text("Keep at least one way to sign in. To remove Apple or Google, add a phone number, email, or another linked account first—or delete your account from Account Management.")
                .fontStyle(.footnote)
        }
    }

    private func phoneMethodRow(session: AuthSession) -> some View {
        signInMethodRow(
            provider: .phone,
            detail: session.phone,
            isLinked: session.hasLinked(.phone),
            linkAction: { linkSheet = .phone }
        )
    }

    private func emailMethodRow(session: AuthSession) -> some View {
        signInMethodRow(
            provider: .email,
            detail: session.email,
            isLinked: session.hasLinked(.email),
            linkAction: { linkSheet = .email }
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
        linkAction: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: provider.systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(provider.securityLabel)
                    .fontStyle(.body)
                if let detail, !detail.isEmpty {
                    Text(detail)
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
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .accessibilityLabel("\(provider.label) linked")
            }
        }
    }

    private func linkedOAuthRow(identity: LinkedIdentity, session: AuthSession) -> some View {
        HStack(spacing: 12) {
            Image(systemName: identity.provider.systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(identity.provider.securityLabel)
                    .fontStyle(.body)
                if let email = identity.email ?? session.email, !email.isEmpty {
                    Text(email)
                        .fontStyle(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            Spacer(minLength: 8)

            Button("Unlink", role: .destructive) {
                prepareUnlink(identity, session: session)
            }
            .fontStyle(.subheadline)
        }
    }

    private var linkAppleRow: some View {
        Button {
            Task { await linkApple() }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: AuthProvider.apple.systemImage)
                    .frame(width: 22)
                Text("Link Sign in with Apple")
                    .fontStyle(.body)
                Spacer()
                if isLinkingApple {
                    ProgressView()
                } else {
                    Text("Link")
                        .fontStyle(.subheadline)
                        .foregroundStyle(Color.primary)
                }
            }
        }
        .disabled(isLinkingApple)
    }

    private var linkGoogleRow: some View {
        Button {
            Task { await linkGoogle() }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: AuthProvider.google.systemImage)
                    .frame(width: 22)
                Text("Link Google")
                    .fontStyle(.body)
                Spacer()
                if isLinkingGoogle {
                    ProgressView()
                } else {
                    Text("Link")
                        .fontStyle(.subheadline)
                        .foregroundStyle(Color.primary)
                }
            }
        }
        .disabled(isLinkingGoogle)
    }

    private func unavailableOAuthRow(provider: AuthProvider) -> some View {
        HStack(spacing: 12) {
            Image(systemName: provider.systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 22)

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

    private func refreshMethods() async {
        isRefreshing = true
        defer { isRefreshing = false }
        await auth.refreshLinkedMethods()
    }

    private func prepareUnlink(_ identity: LinkedIdentity, session: AuthSession) {
        if session.canUnlinkIdentity(identity) {
            identityPendingUnlink = identity
        } else {
            showAddMethodBeforeUnlink = true
        }
    }

    private func unlink(_ identity: LinkedIdentity) async {
        identityPendingUnlink = nil
        do {
            try await auth.unlinkIdentity(identity)
        } catch let error as AuthError where error == .cannotUnlinkLastSignInMethod {
            showAddMethodBeforeUnlink = true
        } catch {
            alertError = PresentableAlertError.from(error)
        }
    }

    private func linkApple() async {
        isLinkingApple = true
        defer { isLinkingApple = false }

        do {
            let authorization = try await AppleSignInCoordinator.requestAuthorization()
            let idToken = try AppleSignInCoordinator.idToken(from: authorization.credential)
            try await auth.linkApple(idToken: idToken, nonce: authorization.rawNonce)
        } catch {
            if let alert = PresentableAlertError.from(error) {
                alertError = alert
            }
        }
    }

    private func linkGoogle() async {
        isLinkingGoogle = true
        defer { isLinkingGoogle = false }

        do {
            try await auth.linkGoogle()
        } catch {
            alertError = PresentableAlertError.from(error)
        }
    }
}

#Preview {
    NavigationStack {
        AccountSecuritySettingsView()
    }
    .environment(AuthStore(service: MockAuthService()))
}
