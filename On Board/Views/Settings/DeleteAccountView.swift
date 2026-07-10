//
//  DeleteAccountView.swift
//  On Board
//

import SwiftUI

struct DeleteAccountView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(BoardStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var hasScrolledToBottom = false
    @State private var showUsernameConfirmation = false
    @State private var typedHandle = ""
    @State private var showFinalWarning = false
    @State private var isDeleting = false
    @State private var alertError: PresentableAlertError?
    @State private var pulseLowOpacity = false

    private var handle: String { store.currentUser?.handle ?? "" }

    private var typedHandleMatches: Bool {
        let trimmed = typedHandle.trimmingCharacters(in: .whitespacesAndNewlines)
        return !handle.isEmpty && trimmed.caseInsensitiveCompare(handle) == .orderedSame
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.red)
                    .padding(.top, 40)

                VStack(spacing: 12) {
                    Text("Delete Account")
                        .fontStyle(.title)
                        .fontWeight(.heavy)

                    Text("Deleting your account will permanently erase:")
                        .fontStyle(.body)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 24)

                VStack(alignment: .leading, spacing: 14) {
                    deletionRow(icon: "person.crop.circle", text: "Your profile — name, handle, bio, and avatar")
                    deletionRow(icon: "square.and.pencil", text: "Every post you've ever made, from all time")
                    deletionRow(icon: "bubble.left", text: "Every comment you've ever made, from all time")
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.red.opacity(0.08))
                }
                .padding(.horizontal, 24)

                VStack(spacing: 6) {
                    Text("This action is irreversible and immediate.")
                        .fontStyle(.headline)
                        .foregroundStyle(.red)
                    Text("There is no grace period — deletion happens the moment you confirm, and On Board cannot recover your account or content afterward.")
                        .fontStyle(.footnote)
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

                Spacer(minLength: 40)

                Button(role: .destructive) {
                    showUsernameConfirmation = true
                } label: {
                    HStack {
                        if isDeleting {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Delete Account")
                                .fontStyle(.headline)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                }
                .buttonStyle(.boardDestructive)
                .disabled(isDeleting || !hasScrolledToBottom)
                .padding(.horizontal, 24)

                if !hasScrolledToBottom {
                    Text("Scroll up to read what will be deleted before continuing.")
                        .fontStyle(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 40)
        }
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y + geometry.containerSize.height >= geometry.contentSize.height - 24
        } action: { _, reachedBottom in
            if reachedBottom { hasScrolledToBottom = true }
        }
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
        .alert("Confirm Deletion", isPresented: $showUsernameConfirmation) {
            TextField("@\(handle)", text: $typedHandle)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Confirm", role: .destructive) {
                showFinalWarning = true
            }
            .disabled(!typedHandleMatches)
            Button("Cancel", role: .cancel) {
                typedHandle = ""
            }
        } message: {
            Text("Type your username, @\(handle), to confirm.")
        }
        .alert("Last chance", isPresented: $showFinalWarning) {
            Button("Delete Account", role: .destructive) {
                Task { await deleteAccount() }
            }
            Button("Cancel", role: .cancel) {
                typedHandle = ""
            }
        } message: {
            Text("This cannot be undone. Your account and everything you've posted will be gone immediately.")
        }
        .authFailureAlert(auth, error: $alertError)
    }

    private func deletionRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.red)
                .frame(width: 20)
            Text(text)
                .fontStyle(.subheadline)
                .foregroundStyle(.primary)
        }
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
    .environment(BoardStore.sampleBoard(currentUserID: SampleProfileID.maya))
}
