import Testing
import SwiftUI
@testable import On_Board

// Quantifies the Host rig's per-frame render cost, old architecture vs
// new, and pins the memo's correctness.
//
// Note on methodology: a geometry-only micro-bench is misleading here —
// stroking a 14-segment path costs ~microseconds, so the OLD version's real
// expense was never the math. It was the view tree: ~50 Shape views diffed
// per frame, ~48 separate rasterization passes, and a compositingGroup
// offscreen pass. So the benchmark renders the FULL view offscreen via
// ImageRenderer: the reconstructed old-style tree vs today's HostFigure
// (one Canvas, memoized silhouette, single-fill sweep).
struct HostRenderCostTests {
    private static let renderSize = CGSize(width: 230, height: 279)

    @Test func memoReturnsStableDilatedPath() {
        let size = Self.renderSize
        let a = HostSilhouetteMemo.dilated(for: .idle, size: size, weight: 0.093)
        let b = HostSilhouetteMemo.dilated(for: .idle, size: size, weight: 0.093)
        #expect(!a.isEmpty)
        #expect(a.boundingRect == b.boundingRect)
        // Dilation must extend beyond the body box on every side.
        let body = HostArt.bodyIdle.path(in: CGRect(origin: .zero, size: size)).boundingRect
        #expect(a.boundingRect.contains(body))
        #expect(a.boundingRect.width > body.width + 0.093 * size.width)
    }

    /// The pre-Canvas implementation, reconstructed minimally: 24 sweep
    /// steps × (stroked fill + fill) as separate Shape views, plus body,
    /// eye, and a compositing group — what HostFigure's body built before.
    private struct OldStyleFigure: View {
        var offset: CGVector

        var body: some View {
            let box = CGRect(origin: .zero, size: HostRenderCostTests.renderSize)
            let bodyPath = HostArt.bodyIdle.path(in: box)
            let style = HostFigure.contourStyle(width: 0.093 * box.width * 2)
            ZStack {
                ForEach(0..<24, id: \.self) { step in
                    let t = CGFloat(step) / 23
                    ZStack {
                        bodyPath.strokedPath(style).fill(.black)
                        bodyPath.fill(.black)
                    }
                    .offset(x: offset.dx * t, y: offset.dy * t)
                }
                bodyPath.fill(.white)
                Circle().fill(.black).frame(width: 60).position(x: 70, y: 65)
            }
            .compositingGroup()
            .rotationEffect(.degrees(-8))
        }
    }

    @MainActor
    @Test func perFrameRenderCostOldVsNew() {
        let frames = 40
        let clock = ContinuousClock()

        // Offsets vary per frame the way an animated pose varies them, so
        // neither side gets to render a fully static frame.
        func offset(_ frame: Int) -> CGVector {
            CGVector(dx: 15 + CGFloat(frame % 5), dy: 19 + CGFloat(frame % 3))
        }

        // Warm both paths once (first-render caches, memo fill).
        _ = ImageRenderer(content: OldStyleFigure(offset: offset(0))).uiImage
        _ = ImageRenderer(content: HostFigure(pose: .degrees(-8)).frame(width: Self.renderSize.width)).uiImage

        let old = clock.measure {
            for frame in 0..<frames {
                let renderer = ImageRenderer(content: OldStyleFigure(offset: offset(frame)))
                _ = renderer.uiImage
            }
        }
        let new = clock.measure {
            for frame in 0..<frames {
                let renderer = ImageRenderer(
                    content: HostFigure(pose: .degrees(-8 + Double(frame % 5)))
                        .frame(width: Self.renderSize.width)
                )
                _ = renderer.uiImage
            }
        }

        let oldMS = Double(old.components.attoseconds) / 1e15 / Double(frames)
        let newMS = Double(new.components.attoseconds) / 1e15 / Double(frames)
        print("HOST-RENDER-BENCH old \(String(format: "%.3f", oldMS))ms/frame  new \(String(format: "%.3f", newMS))ms/frame  ratio \(String(format: "%.1f", oldMS / newMS))x")

        // Loose bound on purpose (simulator timing noise) — this exists to
        // catch an architectural regression (e.g. the memo stops hitting or
        // the sweep goes back to per-view rendering), not to pin a ratio.
        #expect(newMS < oldMS)
    }
}
