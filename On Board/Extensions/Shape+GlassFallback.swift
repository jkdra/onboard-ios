//
//  Shape+GlassFallback.swift
//  On Board
//

import SwiftUI

extension Shape {
    func glassFallback(tone: PostTone) -> some View {
        self
            .fill(.ultraThinMaterial)
            .stroke(tone.color.opacity(0.5), lineWidth: 0.9)
            .fill(tone.color.opacity(0.20))
    }
}
