//
//  NewPostCard.swift
//  On Board
//

import SwiftUI

struct NewPostCard: View {
    var columnWidth: CGFloat = 0
    
    @Environment(\.dynamicTypeSize) private var typeSize
    
    private var cardHeight: CGFloat {
        if typeSize.isAccessibilitySize { return 300 }
        let idealHeight = columnWidth * 1.15
        return max(180, min(idealHeight, 260))
    }
    
    let strokeStyle: StrokeStyle = .init(lineWidth: 4, lineCap: .round, dash: [12])
    
    var body: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .stroke(style: strokeStyle)
            .foregroundStyle(.secondary.opacity(0.45))
            .frame(height: cardHeight)
            .overlay {
                ZStack {
                    Circle()
                        .fill(.secondary.opacity(0.18))
                        .frame(width: 84, height: 84)
                    Image(systemName: "plus")
                        .fontStyle(.title)
                        .foregroundStyle(.secondary)
                }
            }
    }
}
