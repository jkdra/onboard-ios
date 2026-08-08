//
//  AccountSecuritySettingsView.swift
//  On Board
//
//  The section and row builders live in AccountSecuritySettingsView+Views.swift.
//

import AuthenticationServices
import SwiftUI

struct AccountSecuritySettingsView: View {
    // State and stores are not private: the row builders in
    // AccountSecuritySettingsView+Views.swift read and mutate them.
    @Environment(AuthStore.self) var auth
    @Environment(\.colorScheme) private var scheme

    @State var isRefreshing = false
    @State var isLinkingApple = false
    @State var isLinkingGoogle = false
    @State var identityPendingUnlink: LinkedIdentity?
    @State private var showAddMethodBeforeUnlink = false
    @State var linkSheet: LinkSheet?
    @State var showPasswordSheet = false
    @State private var alertError: PresentableAlertError?

    enum LinkSheet: Identifiable {
        case phone(LinkSignInMethodView.Intent)
        case email(LinkSignInMethodView.Intent)

        var id: String {
            switch self {
            case .phone: "phone"
            case .email: "email"
            }
        }
    }

    var body: some View {
        Form {
            traditionalMethodsSection
            thirdPartySection
        }
        .navigationTitle("Security")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refreshMethods() }
        // Pull-to-refresh is an explicit user gesture expecting a signal back —
        // unlike the passive .task/post-link refreshes below, a silent failure
        // here just looks like the pull did nothing.
        .refreshable { await refreshMethods(alertOnFailure: true) }
        .sheet(isPresented: $showPasswordSheet) {
            SetPasswordView {
                Task { await refreshMethods() }
            }
        }
        .sheet(item: $linkSheet) { sheet in
            switch sheet {
            case .phone(let intent):
                LinkSignInMethodView(mode: .phone, intent: intent) {
                    Task { await refreshMethods() }
                }
            case .email(let intent):
                LinkSignInMethodView(mode: .email, intent: intent) {
                    Task { await refreshMethods() }
                }
            }
        }
        .alert(
            "Unlink \(identityPendingUnlink?.provider.label ?? "account")?",
            isPresented: Binding(
                get: { identityPendingUnlink != nil },
                set: { if !$0 { identityPendingUnlink = nil } }
            )
        ) {
            Button("Unlink", role: .destructive) {
                guard let identity = identityPendingUnlink else { return }
                Task { await unlink(identity) }
            }
            Button("Cancel", role: .cancel) { identityPendingUnlink = nil }
        } message: {
            Text("You won't be able to sign in with this method unless you link it again.")
        }
        .alert(
            "Add another sign-in method first",
            isPresented: $showAddMethodBeforeUnlink
        ) {
            Button("Add phone") { linkSheet = .phone(.link) }
            Button("Add email") { linkSheet = .email(.link) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Before removing your last sign-in method, add a phone number, email, or link another account. You can also delete your account from Account Management.")
        }
        .presentableErrorAlert(error: $alertError)
    }

    private func refreshMethods(alertOnFailure: Bool = false) async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            try await auth.refreshLinkedMethods()
        } catch {
            if alertOnFailure {
                alertError = PresentableAlertError.from(error)
            }
        }
    }

    private func unlink(_ identity: LinkedIdentity) async {
        identityPendingUnlink = nil
        do {
            if identity.provider == .apple {
                let authorization = try await AppleSignInCoordinator.requestAuthorization()
                let code = try AppleSignInCoordinator.authorizationCode(from: authorization.credential)
                try await auth.revokeApple(authorizationCode: code)
            }
            try await auth.unlinkIdentity(identity)
        } catch let error as AuthError where error == .cannotUnlinkLastSignInMethod {
            showAddMethodBeforeUnlink = true
        } catch {
            alertError = PresentableAlertError.from(error)
        }
    }

    // Not private: the link rows in AccountSecuritySettingsView+Views.swift
    // trigger these.
    func linkApple() async {
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

    func linkGoogle() async {
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
