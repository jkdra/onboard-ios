//
//  ToastModifier.swift
//  On Board
//

import SwiftUI

struct ToastModifier: ViewModifier {
    let message: String
    let icon: String?
    @Binding var isPresented: Bool
    
    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if isPresented {
                    HStack(spacing: 12) {
                        if let icon {
                            Image(systemName: icon)
                                .fontStyle(.body)
                                .fontWeight(.semibold)
                        }
                        Text(message)
                            .fontStyle(.subheadline)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background {
                        if #available(iOS 26.0, *) {
                            Color.clear.glassEffect(.regular, in: Capsule())
                        } else {
                            Capsule().fill(.regularMaterial)
                        }
                    }
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
                    .padding(.top, 16)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                            withAnimation(.snappy) {
                                isPresented = false
                            }
                        }
                    }
                }
            }
    }
}

extension View {
    func toast(isPresented: Binding<Bool>, message: String, icon: String? = nil) -> some View {
        modifier(ToastModifier(message: message, icon: icon, isPresented: isPresented))
    }
}
