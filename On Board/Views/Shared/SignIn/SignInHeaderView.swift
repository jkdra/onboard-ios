//
//  SignInHeaderView.swift
//  On Board
//

import SwiftUI

struct SignInHeaderView: View {
    let appeared: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            BrandLogo(size: 76)
                .scaleEffect(appeared ? 1 : 0.55)
                .opacity(appeared ? 1 : 0)
        }
    }
}
