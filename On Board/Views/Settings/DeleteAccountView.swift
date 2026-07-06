//
//  DeleteAccountView.swift
//  On Board
//

import SwiftUI

struct DeleteAccountView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    @State private var showDeleteConfirmation = false
    @State private var showDeleteFinalConfirmation = false
    @State private var isDeleting = false
    @State private var alertError: PresentableAlertError?
    @State private var pulseLowOpacity = false
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.red)
                .padding(.top, 40)
            
            VStack(spacing: 12) {
                Text("Delete Account")
                    .fontStyle(.title)
                    .fontWeight(.heavy)
                
                Text("This action is permanent and cannot be undone. All your posts, comments, and profile data will be permanently erased from On Board.")
                    .fontStyle(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 24)
            }
            
            Spacer()
            
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                HStack {
                    if isDeleting {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Permanently Delete Account")
                            .fontStyle(.headline)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(isDeleting)
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            LinearGradient(
                colors: [
                    Color.red.opacity(pulseLowOpacity ? 0.1 : 0.35),
                    Color(.systemBackground)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(
                    .easeInOut(duration: 0.8)
                        .repeatForever(autoreverses: true)
                ) { pulseLowOpacity = true }
            }
        }
        .navigationTitle("Danger Zone")
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

        do {
            if auth.session?.linkedIdentities.contains(where: { $0.provider == .apple }) == true {
                let authorization = try await AppleSignInCoordinator.requestAuthorization()
                let code = try AppleSignInCoordinator.authorizationCode(from: authorization.credential)
                try await auth.revokeApple(authorizationCode: code)
            }

            try await auth.deleteAccount()
        } catch {
            alertError = PresentableAlertError(message: error.localizedDescription)
        }
    }
}

#Preview {
    NavigationStack {
        DeleteAccountView()
    }
    .environment(AuthStore(service: MockAuthService()))
}
