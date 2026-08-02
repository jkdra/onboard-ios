//
//  UpdateAvailableModifier.swift
//  On Board
//
//  Surfaces the version gate. `.recommended` is a dismissible alert;
//  `.required` is a full-screen cover with no way out but the App Store.
//
//  A dismissed soft prompt stays dismissed for that version — nagging on every
//  foreground would train people to dismiss without reading, which is exactly
//  the reflex you don't want the day a `.required` prompt appears.
//

import SwiftUI

struct UpdateAvailableModifier: ViewModifier {
    let requirement: UpdateRequirement

    @Environment(\.openURL) private var openURL
    @AppStorage("update.dismissedForVersion") private var dismissedForVersion = ""
    @State private var showingSoftPrompt = false

    func body(content: Content) -> some View {
        content
            .onChange(of: requirement, initial: true) { _, requirement in
                showingSoftPrompt = requirement == .recommended
                    && dismissedForVersion != AppVersion.current
            }
            .alert("Update available", isPresented: $showingSoftPrompt) {
                Button("Update") { openURL(AppLinks.appStoreURL) }
                Button("Not now", role: .cancel) {
                    dismissedForVersion = AppVersion.current
                }
            } message: {
                Text("A newer version of On Board is available with fixes and improvements.")
            }
            .fullScreenCover(isPresented: .constant(requirement == .required)) {
                VStack(spacing: 20) {
                    Spacer()

                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 52))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)

                    Text("Update required")
                        .font(.title2.weight(.semibold))
                        .multilineTextAlignment(.center)

                    Text("This version of On Board is out of date. Update to keep using the app.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)

                    Spacer()

                    Button {
                        openURL(AppLinks.appStoreURL)
                    } label: {
                        Text("Update On Board")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
                }
                .interactiveDismissDisabled()
            }
    }
}

extension View {
    func updatePrompt(_ requirement: UpdateRequirement) -> some View {
        modifier(UpdateAvailableModifier(requirement: requirement))
    }
}
