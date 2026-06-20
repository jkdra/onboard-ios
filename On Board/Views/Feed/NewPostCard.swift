//
//  NewPostCard.swift
//  On Board
//

import SwiftUI

struct NewPostCard: View {
    
    let strokeStyle: StrokeStyle = .init(lineWidth: 4, lineCap: .round, dash: [12])
    
    var body: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .stroke(style: strokeStyle)
            .foregroundStyle(.secondary.opacity(0.45))
            .frame(height: 200)
            .overlay {
                ZStack {
                    Circle()
                        .fill(.secondary.opacity(0.18))
                        .frame(width: 84, height: 84)
                    Image(systemName: "plus")
                        .font(.title)
                        .foregroundStyle(.secondary)
                }
            }
    }
}
