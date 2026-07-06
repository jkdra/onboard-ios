//
//  OnboardingProgressBar.swift
//  On Board
//

import SwiftUI

struct NamespaceWrapper {
    let id: Namespace.ID
}

struct OnboardingNamespaceKey: EnvironmentKey {
    static var defaultValue: NamespaceWrapper? = nil
}

extension EnvironmentValues {
    var onboardingNamespace: NamespaceWrapper? {
        get { self[OnboardingNamespaceKey.self] }
        set { self[OnboardingNamespaceKey.self] = newValue }
    }
}

struct OnboardingProgressBar: View {
    let step: Int
    var totalSteps: Int = 4
    
    @Environment(\.onboardingNamespace) private var namespace
    
    @State private var shimmerPhase: CGFloat = 0
    @State private var fill: CGFloat = 0

    var shimmerColor: Color = .teal
    var shimmerW: CGFloat = 0.32
    var shimmerDuration: Double = 5.8
    var growDuration: Double = 0.7
    
    private var target: CGFloat {
        min(1, CGFloat(step) / CGFloat(totalSteps))
    }
    
    private var shimmerCenter: CGFloat {
        (-shimmerW) + (fill + shimmerW * 2) * shimmerPhase
    }
    
    var body: some View {
        let content = GeometryReader { proxy in
            ZStack(alignment: .leading) {
                // Background track
                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(0.12))
                
                // Filled track with shimmer mask
                ZStack {
                    Capsule(style: .continuous)
                        .fill(Color.primary)
                    
                    // Shimmer overlay
                    LinearGradient(
                        colors: [.clear, shimmerColor.opacity(0.95), .clear],
                        startPoint: UnitPoint(x: shimmerCenter - shimmerW, y: 0.5),
                        endPoint: UnitPoint(x: shimmerCenter + shimmerW, y: 0.5)
                    )
                    .blendMode(.plusLighter)
                }
                .mask {
                    Capsule(style: .continuous)
                        .frame(width: max(0, proxy.size.width * fill))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(height: 4)
        .onAppear {
            withAnimation(.smooth(duration: 0.8)) { fill = target }
            startShimmer()
        }
        .onChange(of: step) { _, _ in
            withAnimation(.smooth(duration: growDuration)) { fill = target }
        }
        
        if let ns = namespace?.id {
            content.matchedGeometryEffect(id: "onboarding_bar", in: ns)
        } else {
            content
        }
    }
    
    private func startShimmer() {
        shimmerPhase = 0
        withAnimation(
            .easeInOut(duration: shimmerDuration)
                .repeatForever(autoreverses: false)
                .delay(0.3)
        ) {
            shimmerPhase = 1
        }
    }
}

#Preview {
    @Previewable @Namespace var ns
    OnboardingProgressBar(step: 2)
        .padding()
        .environment(\.onboardingNamespace, NamespaceWrapper(id: ns))
}
