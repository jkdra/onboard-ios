//
//  SignInHeaderView.swift
//  On Board
//

import SwiftUI

struct SignInHeaderView: View {
    let appeared: Bool

    var body: some View {
        VStack(spacing: 14) {
            BrandLogo(size: 76)
                .scaleEffect(appeared ? 1 : 0.55)
                .opacity(appeared ? 1 : 0)

            VStack(spacing: 5) {
                Text("On Board")
                    .fontStyle(.largeTitle)
                    .fontWeight(.heavy)
                    .accessibilityAddTraits(.isHeader)

                Text("your weekly bulletin board")
                    .fontStyle(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 10)
        }
    }
}
