//
//  SignInFooterView.swift
//  On Board
//

import SwiftUI

struct SignInFooterView: View {
    let appeared: Bool

    var body: some View {
        Label("Development mode — mock sign-in", systemImage: "hammer.fill")
            .fontStyle(.caption)
            .foregroundStyle(.secondary)
            .opacity(appeared ? 1 : 0)
    }
}
