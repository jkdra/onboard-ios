# Camera Capture, Post-Photo Crop & Optional Display Name — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users take a photo (not just pick one) at every photo-upload site in the app, let them freely crop/reframe post photos (freeform or preset aspect ratios, rule-of-thirds guide) before posting, and make display name genuinely optional end-to-end during onboarding.

**Architecture:** Three independent subsystems sharing only the "get a `UIImage` into the existing upload pipeline" seam:
1. A shared `PhotoSourceButton` (confirmation dialog → camera or `PhotosPicker`) replaces the bare `PhotosPicker` at all four photo-entry sites.
2. A new `PostImageCropView`, built on a pure/testable `PostCropGeometry` math layer, adds resizable-rectangle cropping (freeform + presets) for post photos — mirroring the existing circular `ImageCropView` used for avatars, but with draggable corner handles instead of pan/zoom.
3. The onboarding display-name guard is removed client-side only — the server (`complete_onboarding_profile` RPC) and the `profiles.display_name` column already accept and store an empty string; only the two Swift service implementations currently throw on it.

**Tech Stack:** SwiftUI, `UIViewControllerRepresentable` (for camera capture — SwiftUI has no native camera picker), `PhotosUI`, `Swift Testing`.

## Global Constraints

- Min deployment target iOS 18+; app must build via `xcodebuild -scheme "On Board" -destination "generic/platform=iOS Simulator" build`.
- Tests use **Swift Testing** (`@Test`, `#expect`), not XCTest, in `On BoardTests/`, `@testable import On_Board`.
- The Simulator has no camera hardware — `CameraCaptureView.isAvailable` must be checked before offering "Take Photo," and the app must not crash or show a broken picker when it's false. Real-device verification of the camera path itself is out of scope for this plan's automated steps and must be done manually on a device.
- New/changed crop UI follows `ImageCropView.swift`'s existing visual language: dark background, `.preferredColorScheme(.dark)`, white grid lines, toolbar `Cancel` (leading) / `Confirm` (trailing, `.borderedProminent`).
- No Supabase migration is required anywhere in this plan — confirmed by inspecting the live `complete_onboarding_profile` function and the `profiles` table schema (see Task 10).

---

### Task 1: Camera usage description + capture capability

**Files:**
- Modify: `On-Board-Info.plist`
- Create: `On Board/Utilities/CameraCaptureView.swift`

**Interfaces:**
- Produces: `CameraCaptureView` (`UIViewControllerRepresentable`, `init(onCapture: @escaping (UIImage?) -> Void)`), `CameraCaptureView.isAvailable: Bool` (static).

- [ ] **Step 1: Add the camera usage description**

Add this key to `On-Board-Info.plist`, alongside the existing custom keys (`SupabaseURL`, `GoogleClientID`, etc. — this project puts app-specific keys directly in the base plist rather than as `INFOPLIST_KEY_*` build settings):

```xml
	<key>NSCameraUsageDescription</key>
	<string>On Board uses your camera so you can take a photo directly for your profile picture or a post.</string>
```

- [ ] **Step 2: Write `CameraCaptureView`**

```swift
//
//  CameraCaptureView.swift
//  On Board
//
//  Thin UIViewControllerRepresentable over UIImagePickerController(sourceType: .camera) —
//  SwiftUI has no native camera-capture view. Delegate hands back a UIImage (or nil on cancel).
//

import SwiftUI
import UIKit

struct CameraCaptureView: UIViewControllerRepresentable {
    var onCapture: (UIImage?) -> Void

    static var isAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onCapture: (UIImage?) -> Void

        init(onCapture: @escaping (UIImage?) -> Void) {
            self.onCapture = onCapture
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            onCapture(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCapture(nil)
        }
    }
}
```

- [ ] **Step 3: Build**

Run: `xcodebuild -scheme "On Board" -destination "generic/platform=iOS Simulator" build 2>&1 | grep -E "error:|^\*\* BUILD (SUCCEEDED|FAILED)"`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add "On-Board-Info.plist" "On Board/Utilities/CameraCaptureView.swift"
git commit -m "feat: add camera usage description and CameraCaptureView"
```

---

### Task 2: Shared `PhotoSourceButton`

**Files:**
- Create: `On Board/Views/Shared/PhotoSourceButton.swift`

**Interfaces:**
- Consumes: `CameraCaptureView` (Task 1).
- Produces: `PhotoSourceButton<Label: View>` — `init(selection: Binding<PhotosPickerItem?>, onCapture: @escaping (UIImage) -> Void, label: @escaping () -> Label)`. Drop-in replacement for a bare `PhotosPicker(selection:matching:) { label }`: existing `.buttonStyle`, `.disabled`, `.accessibilityLabel` modifiers at call sites still apply unchanged since this wraps a single `Button`.

- [ ] **Step 1: Write `PhotoSourceButton`**

```swift
//
//  PhotoSourceButton.swift
//  On Board
//
//  Drop-in replacement for a bare PhotosPicker button: offers "Take Photo" /
//  "Choose from Library" via a confirmation dialog. "Take Photo" is hidden
//  when no camera is available (e.g. the Simulator).
//

import PhotosUI
import SwiftUI

struct PhotoSourceButton<Label: View>: View {
    @Binding var selection: PhotosPickerItem?
    var onCapture: (UIImage) -> Void
    @ViewBuilder var label: () -> Label

    @State private var showSourceDialog = false
    @State private var showCamera = false
    @State private var showLibraryPicker = false

    var body: some View {
        Button {
            showSourceDialog = true
        } label: {
            label()
        }
        .confirmationDialog("Add Photo", isPresented: $showSourceDialog, titleVisibility: .hidden) {
            if CameraCaptureView.isAvailable {
                Button("Take Photo") { showCamera = true }
            }
            Button("Choose from Library") { showLibraryPicker = true }
            Button("Cancel", role: .cancel) {}
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraCaptureView { image in
                showCamera = false
                if let image {
                    onCapture(image)
                }
            }
            .ignoresSafeArea()
        }
        .photosPicker(isPresented: $showLibraryPicker, selection: $selection, matching: .images)
    }
}
```

- [ ] **Step 2: Build**

Run: `xcodebuild -scheme "On Board" -destination "generic/platform=iOS Simulator" build 2>&1 | grep -E "error:|^\*\* BUILD (SUCCEEDED|FAILED)"`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add "On Board/Views/Shared/PhotoSourceButton.swift"
git commit -m "feat: add shared PhotoSourceButton (camera + library)"
```

---

### Task 3: `PostCropGeometry` — pure, tested crop math

**Files:**
- Create: `On Board/Utilities/PostCropGeometry.swift`
- Test: `On BoardTests/PostCropGeometryTests.swift`

**Interfaces:**
- Produces: `enum CropCorner { case topLeft, topRight, bottomLeft, bottomRight }`, `enum PostCropGeometry` with static funcs `imageDisplayFrame(imageSize:in:) -> CGRect`, `maxRect(forAspect:in:) -> CGRect`, `anchorPoint(for:in:) -> CGPoint`, `draggedPoint(for:in:) -> CGPoint`, `rect(anchor:draggedPoint:aspect:bounds:) -> CGRect`, `translate(_:by:bounds:) -> CGRect`, `clamp(_:to:) -> CGRect`, `pixelRect(from:imageDisplayFrame:imageSize:) -> CGRect`, `let minCropDimension: CGFloat`.

- [ ] **Step 1: Write the failing tests**

```swift
//
//  PostCropGeometryTests.swift
//  On BoardTests
//

import Foundation
import Testing
@testable import On_Board

struct PostCropGeometryTests {

    @Test func imageDisplayFrameFitsWideImageByWidth() {
        // 2:1 image in a square container fits by width, letterboxed vertically.
        let frame = PostCropGeometry.imageDisplayFrame(
            imageSize: CGSize(width: 200, height: 100),
            in: CGSize(width: 100, height: 100)
        )
        #expect(frame.width == 100)
        #expect(frame.height == 50)
        #expect(frame.minY == 25)
    }

    @Test func imageDisplayFrameFitsTallImageByHeight() {
        let frame = PostCropGeometry.imageDisplayFrame(
            imageSize: CGSize(width: 100, height: 200),
            in: CGSize(width: 100, height: 100)
        )
        #expect(frame.height == 100)
        #expect(frame.width == 50)
        #expect(frame.minX == 25)
    }

    @Test func maxRectNilAspectReturnsFullFrame() {
        let frame = CGRect(x: 0, y: 0, width: 100, height: 50)
        #expect(PostCropGeometry.maxRect(forAspect: nil, in: frame) == frame)
    }

    @Test func maxRectSquareInWideFrameFitsByHeight() {
        let frame = CGRect(x: 0, y: 0, width: 100, height: 50)
        let square = PostCropGeometry.maxRect(forAspect: 1.0, in: frame)
        #expect(square.width == 50)
        #expect(square.height == 50)
        #expect(square.midX == frame.midX)
        #expect(square.midY == frame.midY)
    }

    @Test func rectFreeformDragGrowsFromAnchor() {
        let bounds = CGRect(x: 0, y: 0, width: 200, height: 200)
        let result = PostCropGeometry.rect(
            anchor: CGPoint(x: 20, y: 20),
            draggedPoint: CGPoint(x: 120, y: 80),
            aspect: nil,
            bounds: bounds
        )
        #expect(result == CGRect(x: 20, y: 20, width: 100, height: 60))
    }

    @Test func rectHonorsAspectFromWidth() {
        let bounds = CGRect(x: 0, y: 0, width: 200, height: 200)
        // width dominates (100 vs height 60) at aspect 1:1 -> width wins, height matches it.
        let result = PostCropGeometry.rect(
            anchor: CGPoint(x: 0, y: 0),
            draggedPoint: CGPoint(x: 100, y: 60),
            aspect: 1.0,
            bounds: bounds
        )
        #expect(result.width == 100)
        #expect(result.height == 100)
    }

    @Test func rectEnforcesMinimumDimension() {
        let bounds = CGRect(x: 0, y: 0, width: 200, height: 200)
        let result = PostCropGeometry.rect(
            anchor: CGPoint(x: 20, y: 20),
            draggedPoint: CGPoint(x: 25, y: 22),
            aspect: nil,
            bounds: bounds
        )
        #expect(result.width == PostCropGeometry.minCropDimension)
        #expect(result.height == PostCropGeometry.minCropDimension)
    }

    @Test func rectClampsToBounds() {
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
        let result = PostCropGeometry.rect(
            anchor: CGPoint(x: 80, y: 80),
            draggedPoint: CGPoint(x: 300, y: 300),
            aspect: nil,
            bounds: bounds
        )
        #expect(result.maxX <= 100)
        #expect(result.maxY <= 100)
    }

    @Test func translateClampsInsideBounds() {
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
        let rect = CGRect(x: 10, y: 10, width: 30, height: 30)
        let moved = PostCropGeometry.translate(rect, by: CGSize(width: 1000, height: -1000), bounds: bounds)
        #expect(moved.minX == 70)
        #expect(moved.minY == 0)
    }

    @Test func pixelRectMapsDisplaySpaceToImagePixels() {
        // Image is 400x200 (2:1), displayed at 100x50 inside a larger frame with a 25pt x-offset.
        let imageDisplayFrame = CGRect(x: 25, y: 0, width: 100, height: 50)
        let displayRect = CGRect(x: 25, y: 0, width: 50, height: 25)
        let pixelRect = PostCropGeometry.pixelRect(
            from: displayRect,
            imageDisplayFrame: imageDisplayFrame,
            imageSize: CGSize(width: 400, height: 200)
        )
        #expect(pixelRect == CGRect(x: 0, y: 0, width: 200, height: 100))
    }

    @Test func anchorAndDraggedPointAreOppositeCorners() {
        let rect = CGRect(x: 10, y: 20, width: 30, height: 40)
        #expect(PostCropGeometry.anchorPoint(for: .topLeft, in: rect) == CGPoint(x: 40, y: 60))
        #expect(PostCropGeometry.draggedPoint(for: .topLeft, in: rect) == CGPoint(x: 10, y: 20))
        #expect(PostCropGeometry.anchorPoint(for: .bottomRight, in: rect) == CGPoint(x: 10, y: 20))
        #expect(PostCropGeometry.draggedPoint(for: .bottomRight, in: rect) == CGPoint(x: 40, y: 60))
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodebuild test -scheme "On Board" -destination "platform=iOS Simulator,name=iPhone 16 Pro,OS=18.5" -only-testing "On BoardTests/PostCropGeometryTests" -parallel-testing-enabled NO`
Expected: FAIL — `PostCropGeometry` does not exist yet (compile error).

- [ ] **Step 3: Implement `PostCropGeometry`**

```swift
//
//  PostCropGeometry.swift
//  On Board
//
//  Pure geometry for PostImageCropView's freeform/aspect-constrained crop
//  rectangle. No SwiftUI/UIKit dependency beyond CoreGraphics types, so it's
//  fully unit-testable without rendering anything.
//

import CoreGraphics

enum CropCorner: CaseIterable {
    case topLeft, topRight, bottomLeft, bottomRight
}

enum PostCropGeometry {
    /// Smallest allowed crop-rect side, in points, on either axis.
    static let minCropDimension: CGFloat = 60

    /// Where `imageSize` lands inside `containerSize` under `.scaledToFit()`.
    static func imageDisplayFrame(imageSize: CGSize, in containerSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0,
              containerSize.width > 0, containerSize.height > 0 else {
            return CGRect(origin: .zero, size: containerSize)
        }
        let imageAspect = imageSize.width / imageSize.height
        let containerAspect = containerSize.width / containerSize.height
        let displaySize: CGSize
        if imageAspect > containerAspect {
            displaySize = CGSize(width: containerSize.width, height: containerSize.width / imageAspect)
        } else {
            displaySize = CGSize(width: containerSize.height * imageAspect, height: containerSize.height)
        }
        let origin = CGPoint(
            x: (containerSize.width - displaySize.width) / 2,
            y: (containerSize.height - displaySize.height) / 2
        )
        return CGRect(origin: origin, size: displaySize)
    }

    /// The largest rect of `aspect` (width / height) centered within `frame`.
    /// `aspect == nil` (freeform) returns `frame` itself, uncropped.
    static func maxRect(forAspect aspect: CGFloat?, in frame: CGRect) -> CGRect {
        guard let aspect, aspect > 0 else { return frame }
        let frameAspect = frame.width / frame.height
        let size: CGSize
        if aspect > frameAspect {
            size = CGSize(width: frame.width, height: frame.width / aspect)
        } else {
            size = CGSize(width: frame.height * aspect, height: frame.height)
        }
        return CGRect(
            x: frame.midX - size.width / 2,
            y: frame.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    /// The corner point that stays fixed while `corner` is being dragged.
    static func anchorPoint(for corner: CropCorner, in rect: CGRect) -> CGPoint {
        draggedPoint(for: opposite(of: corner), in: rect)
    }

    /// The point of `rect` that a given corner's drag handle sits on.
    static func draggedPoint(for corner: CropCorner, in rect: CGRect) -> CGPoint {
        switch corner {
        case .topLeft: return CGPoint(x: rect.minX, y: rect.minY)
        case .topRight: return CGPoint(x: rect.maxX, y: rect.minY)
        case .bottomLeft: return CGPoint(x: rect.minX, y: rect.maxY)
        case .bottomRight: return CGPoint(x: rect.maxX, y: rect.maxY)
        }
    }

    private static func opposite(of corner: CropCorner) -> CropCorner {
        switch corner {
        case .topLeft: return .bottomRight
        case .topRight: return .bottomLeft
        case .bottomLeft: return .topRight
        case .bottomRight: return .topLeft
        }
    }

    /// Builds a rect from a fixed `anchor` corner and the live `draggedPoint`
    /// of the opposite corner, honoring `aspect` (nil = free), a minimum
    /// size, and `bounds` clamping.
    static func rect(anchor: CGPoint, draggedPoint: CGPoint, aspect: CGFloat?, bounds: CGRect) -> CGRect {
        var point = draggedPoint
        point.x = min(max(point.x, bounds.minX), bounds.maxX)
        point.y = min(max(point.y, bounds.minY), bounds.maxY)

        var width = abs(point.x - anchor.x)
        var height = abs(point.y - anchor.y)

        if let aspect, aspect > 0 {
            if width / max(height, 1) > aspect {
                width = height * aspect
            } else {
                height = width / aspect
            }
        }

        width = max(width, minCropDimension)
        height = max(height, minCropDimension)

        let originX = point.x >= anchor.x ? anchor.x : anchor.x - width
        let originY = point.y >= anchor.y ? anchor.y : anchor.y - height

        return clamp(CGRect(x: originX, y: originY, width: width, height: height), to: bounds)
    }

    /// Moves `rect` by `translation`, clamped so it stays fully inside `bounds`.
    static func translate(_ rect: CGRect, by translation: CGSize, bounds: CGRect) -> CGRect {
        var r = rect
        r.origin.x += translation.width
        r.origin.y += translation.height
        return clamp(r, to: bounds)
    }

    static func clamp(_ rect: CGRect, to bounds: CGRect) -> CGRect {
        var r = rect
        r.size.width = min(r.width, bounds.width)
        r.size.height = min(r.height, bounds.height)
        if r.minX < bounds.minX { r.origin.x = bounds.minX }
        if r.minY < bounds.minY { r.origin.y = bounds.minY }
        if r.maxX > bounds.maxX { r.origin.x = bounds.maxX - r.width }
        if r.maxY > bounds.maxY { r.origin.y = bounds.maxY - r.height }
        return r
    }

    /// Maps a crop rect from on-screen display coordinates into the source
    /// image's pixel coordinates, given where the image was displayed.
    static func pixelRect(from displayRect: CGRect, imageDisplayFrame: CGRect, imageSize: CGSize) -> CGRect {
        guard imageDisplayFrame.width > 0 else { return .zero }
        let scale = imageSize.width / imageDisplayFrame.width
        return CGRect(
            x: (displayRect.minX - imageDisplayFrame.minX) * scale,
            y: (displayRect.minY - imageDisplayFrame.minY) * scale,
            width: displayRect.width * scale,
            height: displayRect.height * scale
        )
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `xcodebuild test -scheme "On Board" -destination "platform=iOS Simulator,name=iPhone 16 Pro,OS=18.5" -only-testing "On BoardTests/PostCropGeometryTests" -parallel-testing-enabled NO`
Expected: PASS (all 11 tests)

- [ ] **Step 5: Commit**

```bash
git add "On Board/Utilities/PostCropGeometry.swift" "On BoardTests/PostCropGeometryTests.swift"
git commit -m "feat: add PostCropGeometry crop-rect math with tests"
```

---

### Task 4: `PostImageCropView`

**Files:**
- Create: `On Board/Views/Shared/PostImageCropView.swift`

**Interfaces:**
- Consumes: `PostCropGeometry`, `CropCorner` (Task 3); `View.reverseMask(alignment:_:)` (already defined in `ImageCropView.swift`, module-wide — no changes needed there).
- Produces: `PostImageCropView` (`init(image: UIImage, onCrop: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void)`), `enum CropAspectOption: CaseIterable, Identifiable { case free, square, portrait45, landscape169, original }` with `var ratio: CGFloat?` and `var label: String`.

- [ ] **Step 1: Write `PostImageCropView`**

```swift
//
//  PostImageCropView.swift
//  On Board
//
//  Rectangular photo crop tool for post photos: freeform (drag corner
//  handles) or a preset aspect ratio, with a rule-of-thirds guide sized to
//  the current crop rect. Distinct from ImageCropView (circular avatar crop,
//  pan/zoom-the-image model) — here the image is static and the crop
//  rectangle itself is resized/moved, matching a Photos-app-style crop tool.
//

import SwiftUI
import UIKit

enum CropAspectOption: CaseIterable, Identifiable {
    case free, square, portrait45, landscape169, original

    var id: Self { self }

    var ratio: CGFloat? {
        switch self {
        case .free: return nil
        case .square: return 1.0
        case .portrait45: return 4.0 / 5.0
        case .landscape169: return 16.0 / 9.0
        case .original: return nil // resolved against the image's own aspect at use site
        }
    }

    var label: String {
        switch self {
        case .free: return "Free"
        case .square: return "1:1"
        case .portrait45: return "4:5"
        case .landscape169: return "16:9"
        case .original: return "Original"
        }
    }
}

struct PostImageCropView: View {
    let image: UIImage
    var onCrop: (UIImage) -> Void
    var onCancel: () -> Void

    @State private var cropRect: CGRect = .zero
    @State private var selectedAspect: CropAspectOption = .free
    @State private var dragStartRect: CGRect?

    private let padding: CGFloat = 16
    private let handleSize: CGFloat = 28
    private let settleAnimation: Animation = .smooth(duration: 0.25)

    private var imageAspect: CGFloat { image.size.width / image.size.height }

    /// `.original` isn't a fixed ratio — it's whatever the source image's own aspect is.
    private func resolvedRatio(for option: CropAspectOption) -> CGFloat? {
        option == .original ? imageAspect : option.ratio
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                GeometryReader { geometry in
                    let containerSize = CGSize(
                        width: geometry.size.width - padding * 2,
                        height: geometry.size.height - padding * 2
                    )
                    let displayFrame = PostCropGeometry.imageDisplayFrame(imageSize: image.size, in: containerSize)
                        .offsetBy(dx: padding, dy: padding)

                    ZStack {
                        Image(uiImage: image)
                            .resizable()
                            .frame(width: displayFrame.width, height: displayFrame.height)
                            .position(x: displayFrame.midX, y: displayFrame.midY)

                        Rectangle()
                            .fill(Color.black.opacity(0.6))
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .reverseMask {
                                Rectangle().frame(width: cropRect.width, height: cropRect.height)
                                    .position(x: cropRect.midX, y: cropRect.midY)
                            }
                            .allowsHitTesting(false)

                        cropOverlay(in: displayFrame)
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .onAppear {
                        cropRect = PostCropGeometry.maxRect(forAspect: resolvedRatio(for: selectedAspect), in: displayFrame)
                    }
                    .onChange(of: selectedAspect) { _, newValue in
                        withAnimation(settleAnimation) {
                            cropRect = PostCropGeometry.maxRect(forAspect: resolvedRatio(for: newValue), in: displayFrame)
                        }
                    }
                }
                .background(Color.black.ignoresSafeArea())
                .clipped()

                aspectPicker
                    .padding(.vertical, 14)
                    .background(Color.black)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Adjust Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { onCancel() } label: {
                        Label("Cancel", systemImage: "xmark").fontWeight(.semibold)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { confirmCrop() } label: {
                        Label("Confirm", systemImage: "checkmark").fontWeight(.semibold)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Crop rectangle + handles

    @ViewBuilder
    private func cropOverlay(in displayFrame: CGRect) -> some View {
        ZStack {
            Rectangle()
                .stroke(Color.white, lineWidth: 2)
                .frame(width: cropRect.width, height: cropRect.height)
                .position(x: cropRect.midX, y: cropRect.midY)

            gridLines

            Color.clear
                .contentShape(Rectangle())
                .frame(width: cropRect.width, height: cropRect.height)
                .position(x: cropRect.midX, y: cropRect.midY)
                .gesture(moveGesture(in: displayFrame))

            ForEach(CropCorner.allCases, id: \.self) { corner in
                handle(for: corner, in: displayFrame)
            }
        }
    }

    private var gridLines: some View {
        ZStack {
            Rectangle().fill(Color.white.opacity(0.3)).frame(width: 1, height: cropRect.height)
                .position(x: cropRect.minX + cropRect.width / 3, y: cropRect.midY)
            Rectangle().fill(Color.white.opacity(0.3)).frame(width: 1, height: cropRect.height)
                .position(x: cropRect.minX + cropRect.width * 2 / 3, y: cropRect.midY)
            Rectangle().fill(Color.white.opacity(0.3)).frame(width: cropRect.width, height: 1)
                .position(x: cropRect.midX, y: cropRect.minY + cropRect.height / 3)
            Rectangle().fill(Color.white.opacity(0.3)).frame(width: cropRect.width, height: 1)
                .position(x: cropRect.midX, y: cropRect.minY + cropRect.height * 2 / 3)
        }
        .allowsHitTesting(false)
    }

    private func handle(for corner: CropCorner, in displayFrame: CGRect) -> some View {
        let point = PostCropGeometry.draggedPoint(for: corner, in: cropRect)
        return Circle()
            .fill(Color.white)
            .frame(width: handleSize, height: handleSize)
            .shadow(radius: 2)
            .position(point)
            .gesture(resizeGesture(for: corner, in: displayFrame))
            .accessibilityLabel("Resize crop — \(corner)")
    }

    private func resizeGesture(for corner: CropCorner, in displayFrame: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let start = dragStartRect ?? cropRect
                if dragStartRect == nil { dragStartRect = start }
                let anchor = PostCropGeometry.anchorPoint(for: corner, in: start)
                let origin = PostCropGeometry.draggedPoint(for: corner, in: start)
                let newPoint = CGPoint(
                    x: origin.x + value.translation.width,
                    y: origin.y + value.translation.height
                )
                cropRect = PostCropGeometry.rect(
                    anchor: anchor,
                    draggedPoint: newPoint,
                    aspect: resolvedRatio(for: selectedAspect),
                    bounds: displayFrame
                )
            }
            .onEnded { _ in dragStartRect = nil }
    }

    private func moveGesture(in displayFrame: CGRect) -> some Gesture {
        DragGesture()
            .onChanged { value in
                let start = dragStartRect ?? cropRect
                if dragStartRect == nil { dragStartRect = start }
                cropRect = PostCropGeometry.translate(start, by: value.translation, bounds: displayFrame)
            }
            .onEnded { _ in dragStartRect = nil }
    }

    // MARK: - Aspect picker

    private var aspectPicker: some View {
        HStack(spacing: 10) {
            ForEach(CropAspectOption.allCases) { option in
                Button {
                    selectedAspect = option
                } label: {
                    Text(option.label)
                        .fontStyle(.footnote)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            selectedAspect == option ? Color.white : Color.white.opacity(0.15),
                            in: Capsule()
                        )
                        .foregroundStyle(selectedAspect == option ? .black : .white)
                }
            }
        }
    }

    // MARK: - Crop rendering

    private func confirmCrop() {
        // GeometryReader's displayFrame isn't available here, so recompute the
        // same padded frame confirmCrop needs from cropRect's own bookkeeping:
        // cropRect was always produced from a displayFrame with the same
        // padding, so pixelRect only needs *a* displayFrame with the correct
        // scale — recomputed fresh from the image's natural size vs. the
        // crop rect's own containing bounds captured at last layout.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true

        let pixelRect = PostCropGeometry.pixelRect(
            from: cropRect,
            imageDisplayFrame: lastDisplayFrame,
            imageSize: image.size
        )
        let renderer = UIGraphicsImageRenderer(size: pixelRect.size, format: format)
        let cropped = renderer.image { _ in
            image.draw(at: CGPoint(x: -pixelRect.origin.x, y: -pixelRect.origin.y))
        }
        onCrop(cropped)
    }

    @State private var lastDisplayFrame: CGRect = .zero
}

#Preview {
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 800))
    let dummyImage = renderer.image { ctx in
        UIColor.systemBlue.setFill()
        ctx.fill(CGRect(x: 0, y: 0, width: 1200, height: 800))
    }
    return PostImageCropView(image: dummyImage, onCrop: { _ in }, onCancel: {})
}
```

- [ ] **Step 2: Fix the `displayFrame` capture gap**

The sketch above calls out its own problem: `confirmCrop()` needs the same `displayFrame` the `GeometryReader` computed, but that value is local to the `GeometryReader` closure. Track it in the `lastDisplayFrame` state declared above by setting it wherever `displayFrame` is computed inside `GeometryReader`. Update the `GeometryReader` body so its `let displayFrame = ...` line is followed by:

```swift
                    Color.clear
                        .onAppear { lastDisplayFrame = displayFrame }
                        .onChange(of: geometry.size) { _, _ in lastDisplayFrame = displayFrame }
```

placed as the first element in the outer `ZStack` (before `Image(uiImage: image)`), so `lastDisplayFrame` is always current when `confirmCrop()` runs. (`cropRect`'s own `.onAppear`/`.onChange(of: selectedAspect)` already depend on `displayFrame` being correct at the same moments, so this piggybacks on the same recomputation points plus orientation/size changes.)

- [ ] **Step 3: Build**

Run: `xcodebuild -scheme "On Board" -destination "generic/platform=iOS Simulator" build 2>&1 | grep -E "error:|^\*\* BUILD (SUCCEEDED|FAILED)"`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Manual verification in Simulator**

Run the app (mock mode is fine — this view has no network dependency), open the Preview canvas or wire it temporarily behind a debug button, and confirm:
- Dragging any corner handle resizes the rect and stays clamped inside the image.
- Dragging inside the rect moves it without resizing.
- Tapping "1:1", "4:5", "16:9" snaps the rect to that ratio, centered, at max size.
- Tapping "Free" after a preset allows independent width/height dragging again.
- "Confirm" produces a cropped image matching the visible rect (spot-check by wiring `onCrop` to print the result's `size`).

- [ ] **Step 5: Commit**

```bash
git add "On Board/Views/Shared/PostImageCropView.swift"
git commit -m "feat: add PostImageCropView (freeform + preset aspect ratio crop)"
```

---

### Task 5: Fix `ImageUploader` for cropped post photos

**Files:**
- Modify: `On Board/Utilities/ImageProcessor.swift`
- Modify: `On Board/Utilities/PostImageUploader.swift`
- Test: `On BoardTests/ImageProcessorTests.swift`

**Interfaces:**
- Consumes: `PhotoType` (existing).
- Produces: `ImageProcessor.processPostPhoto(_ image: UIImage) -> Data?` (new overload, distinct from the existing `processPostPhoto(from: Data)`).

**Why this task exists:** `PostImageUploader.swift`'s `.uiImage` case only calls `ImageProcessor.processProfilePicture` when `type == .profilePicture`; for any other `PhotoType` it falls back to `image.jpegData(compressionQuality:)` with **no downscaling**. Task 6/7 route freshly-cropped post photos through `.uiImage(cropped)` with `type: .postPhoto` — without this fix, a cropped post photo would upload at full, undownscaled resolution.

- [ ] **Step 1: Write the failing test**

```swift
//
//  ImageProcessorTests.swift
//  On BoardTests
//

import Foundation
import Testing
import UIKit
@testable import On_Board

@MainActor
struct ImageProcessorTests {

    private func solidImage(width: CGFloat, height: CGFloat) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
        return renderer.image { ctx in
            UIColor.systemBlue.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    @Test func processPostPhotoDownscalesToMaxDimension() {
        let oversized = solidImage(width: 4000, height: 2000)
        guard let data = ImageProcessor.processPostPhoto(oversized) else {
            Issue.record("Expected non-nil JPEG data")
            return
        }
        guard let decoded = UIImage(data: data) else {
            Issue.record("Expected decodable JPEG data")
            return
        }
        #expect(decoded.size.width <= PhotoType.postPhoto.maxDimension)
        #expect(decoded.size.height <= PhotoType.postPhoto.maxDimension)
    }

    @Test func processPostPhotoLeavesSmallImageUnscaled() {
        let small = solidImage(width: 300, height: 200)
        guard let data = ImageProcessor.processPostPhoto(small),
              let decoded = UIImage(data: data) else {
            Issue.record("Expected decodable JPEG data")
            return
        }
        #expect(decoded.size.width == 300)
        #expect(decoded.size.height == 200)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild test -scheme "On Board" -destination "platform=iOS Simulator,name=iPhone 16 Pro,OS=18.5" -only-testing "On BoardTests/ImageProcessorTests" -parallel-testing-enabled NO`
Expected: FAIL — `ImageProcessor.processPostPhoto(_ image: UIImage)` does not exist (the only existing overload takes `Data`, causing a compile error at the call site).

- [ ] **Step 3: Add `processPostPhoto(_ image: UIImage)`**

In `On Board/Utilities/ImageProcessor.swift`, add this method to `enum ImageProcessor` (near `processProfilePicture`):

```swift
    /// Processes a pre-cropped UIImage for a post photo (e.g. output of
    /// PostImageCropView). Mirrors processProfilePicture's scale-then-encode
    /// shape but uses PhotoType.postPhoto's larger maxDimension/quality.
    nonisolated static func processPostPhoto(_ image: UIImage) -> Data? {
        let type = PhotoType.postPhoto
        let scaledImage = image.scaledDown(toMaxDimension: type.maxDimension)
        return scaledImage.jpegData(compressionQuality: type.compressionQuality)
    }
```

- [ ] **Step 4: Route `.uiImage` uploads through the correct processor per `PhotoType`**

In `On Board/Utilities/PostImageUploader.swift`, replace the `.uiImage` case:

```swift
            case .uiImage(let image):
                if case .profilePicture = type {
                    data = ImageProcessor.processProfilePicture(image)
                } else {
                    // Fallback if somehow post uses UIImage
                    data = image.jpegData(compressionQuality: type.compressionQuality)
                }
```

with:

```swift
            case .uiImage(let image):
                switch type {
                case .profilePicture:
                    data = ImageProcessor.processProfilePicture(image)
                case .postPhoto:
                    data = ImageProcessor.processPostPhoto(image)
                }
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `xcodebuild test -scheme "On Board" -destination "platform=iOS Simulator,name=iPhone 16 Pro,OS=18.5" -only-testing "On BoardTests/ImageProcessorTests" -parallel-testing-enabled NO`
Expected: PASS (both tests)

- [ ] **Step 6: Commit**

```bash
git add "On Board/Utilities/ImageProcessor.swift" "On Board/Utilities/PostImageUploader.swift" "On BoardTests/ImageProcessorTests.swift"
git commit -m "fix: downscale UIImage post-photo uploads to PhotoType.postPhoto's maxDimension"
```

---

### Task 6: Wire camera + crop into `NewPostView`

**Files:**
- Modify: `On Board/Views/Feed/NewPostView.swift`

**Interfaces:**
- Consumes: `PhotoSourceButton` (Task 2), `PostImageCropView` (Task 4), `ImageUploader.upload(input:type:userID:)` (existing, now fixed by Task 5).

- [ ] **Step 1: Add crop state**

In the "Image attachment" `@State` block (around line 31), add:

```swift
    @State private var uncroppedPostImage: UIImage?
```

- [ ] **Step 2: Replace the `PhotosPicker` in `imageAttachmentRow`**

Replace:

```swift
                let hasImage = selectedPhotoData != nil
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Label(
                        hasImage ? "Change Image" : "Add Image",
                        systemImage: "photo.badge.plus"
                    )
                }
                .buttonStyle(.boardSecondary)
                .disabled(isUploadingImage)
```

with:

```swift
                let hasImage = selectedPhotoData != nil
                PhotoSourceButton(selection: $selectedPhotoItem, onCapture: { uncroppedPostImage = $0 }) {
                    Label(
                        hasImage ? "Change Image" : "Add Image",
                        systemImage: "photo.badge.plus"
                    )
                }
                .buttonStyle(.boardSecondary)
                .disabled(isUploadingImage)
```

- [ ] **Step 3: Present the crop sheet and replace the upload flow**

Add this modifier to the `NavigationStack` in `body` (near the existing `.sheet(isPresented: $showingTagSelection)`):

```swift
            .fullScreenCover(item: Binding<UIImage?>(
                get: { uncroppedPostImage },
                set: { uncroppedPostImage = $0 }
            )) { image in
                PostImageCropView(image: image) { cropped in
                    uncroppedPostImage = nil
                    Task { await uploadCroppedImage(cropped) }
                } onCancel: {
                    uncroppedPostImage = nil
                    selectedPhotoItem = nil
                }
            }
```

Replace the `.onChange(of: selectedPhotoItem)` handler:

```swift
            .onChange(of: selectedPhotoItem) { _, item in
                Task { await loadAndUpload(item) }
            }
```

with:

```swift
            .onChange(of: selectedPhotoItem) { _, item in
                Task { await loadPickedPhoto(item) }
            }
```

- [ ] **Step 4: Replace `loadAndUpload(_:)` with a load step + a crop-confirm upload step**

Replace the existing `loadAndUpload(_:)` method:

```swift
    @MainActor
    private func loadAndUpload(_ item: PhotosPickerItem?) async {
        guard let item else { return }

        guard let rawData = try? await item.loadTransferable(type: Data.self),
              UIImage(data: rawData) != nil else { return }

        // Show the original immediately as a preview (UIImage can't display its own WebP output).
        selectedPhotoData = rawData

        guard let userID = store.currentUserID else { return }

        isUploadingImage = true
        defer { isUploadingImage = false }

        // Encode (JPEG, downscaled) + upload via the shared helper, which now runs the
        // CPU-heavy encode OFF the main actor so the composer doesn't hitch.
        if let result = await ImageUploader.upload(input: .rawData(rawData), type: .postPhoto, userID: userID) {
            uploadedImageUrl = result.url
            uploadedAspectRatio = result.aspectRatio
        } else {
            // Encode/upload failed — post goes text-only; preview stays so user sees their image.
            uploadedImageUrl = nil
            uploadedAspectRatio = nil
        }
    }
```

with:

```swift
    @MainActor
    private func loadPickedPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        guard let rawData = try? await item.loadTransferable(type: Data.self),
              let uiImage = UIImage(data: rawData) else { return }
        uncroppedPostImage = uiImage
    }

    private func uploadCroppedImage(_ image: UIImage) async {
        // Optimistic preview of the cropped result while it uploads.
        selectedPhotoData = image.jpegData(compressionQuality: 0.85)

        guard let userID = store.currentUserID else { return }

        isUploadingImage = true
        defer { isUploadingImage = false }

        if let result = await ImageUploader.upload(input: .uiImage(image), type: .postPhoto, userID: userID) {
            uploadedImageUrl = result.url
            uploadedAspectRatio = result.aspectRatio
        } else {
            // Upload failed — post goes text-only; preview stays so user sees their image.
            uploadedImageUrl = nil
            uploadedAspectRatio = nil
        }
    }
```

Note: `removeImage()`, `canSubmit`, and `submit()` are unchanged — they only reference `selectedPhotoData`/`uploadedImageUrl`/`uploadedAspectRatio`, which keep the same meaning.

- [ ] **Step 5: Build**

Run: `xcodebuild -scheme "On Board" -destination "generic/platform=iOS Simulator" build 2>&1 | grep -E "error:|^\*\* BUILD (SUCCEEDED|FAILED)"`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Manual verification**

Launch the app in mock mode, open "New Post," tap "Add Image":
- "Choose from Library" → pick a photo → crop sheet appears → confirm → image preview updates in the composer.
- "Take Photo" is hidden in the Simulator (no camera hardware) — confirm no crash, dialog just shows "Choose from Library" / "Cancel".
- Cancelling the crop sheet leaves the composer with no image attached (not a stale preview).

- [ ] **Step 7: Commit**

```bash
git add "On Board/Views/Feed/NewPostView.swift"
git commit -m "feat: camera capture + crop for new-post photos"
```

---

### Task 7: Wire camera + crop into post editing

**Files:**
- Modify: `On Board/Views/Post/PostDetailView.swift`
- Modify: `On Board/Views/Post/PostDetailView+Views.swift`
- Modify: `On Board/Views/Post/PostDetailView+Logic.swift`

**Interfaces:**
- Consumes: `PhotoSourceButton` (Task 2), `PostImageCropView` (Task 4), `ImageUploader.upload(input:type:userID:)` (Task 5).

- [ ] **Step 1: Add crop state**

In `PostDetailView.swift`, in the "Image editing" `@State` block (around line 33), add:

```swift
    @State var uncroppedEditImage: UIImage?
```

- [ ] **Step 2: Present the crop sheet**

In `PostDetailView.swift`, near the existing `.onChange(of: selectedEditPhotoItem)` (around line 264), replace:

```swift
            .onChange(of: selectedEditPhotoItem) { _, item in
                Task { await loadAndUploadEditImage(item) }
            }
```

with:

```swift
            .onChange(of: selectedEditPhotoItem) { _, item in
                Task { await loadEditImage(item) }
            }
            .fullScreenCover(item: Binding<UIImage?>(
                get: { uncroppedEditImage },
                set: { uncroppedEditImage = $0 }
            )) { image in
                PostImageCropView(image: image) { cropped in
                    uncroppedEditImage = nil
                    Task { await uploadCroppedEditImage(cropped) }
                } onCancel: {
                    uncroppedEditImage = nil
                    selectedEditPhotoItem = nil
                }
            }
```

- [ ] **Step 3: Replace both `PhotosPicker` call sites in `PostDetailView+Views.swift`**

Replace (around line 420, the "Change" pill on an existing image):

```swift
                PhotosPicker(selection: $selectedEditPhotoItem, matching: .images) {
                    Label("Change", systemImage: "camera.fill")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(.thinMaterial, in: Capsule())
                }
                .disabled(isUploadingEditImage)
                .padding(10)
```

with:

```swift
                PhotoSourceButton(selection: $selectedEditPhotoItem, onCapture: { uncroppedEditImage = $0 }) {
                    Label("Change", systemImage: "camera.fill")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(.thinMaterial, in: Capsule())
                }
                .disabled(isUploadingEditImage)
                .padding(10)
```

Replace (around line 433, the dashed "no image" target):

```swift
            PhotosPicker(selection: $selectedEditPhotoItem, matching: .images) {
                HStack(spacing: 10) {
                    Image(systemName: "photo.badge.plus")
                        .font(.title3)
                    Text("Add a photo")
                        .font(.subheadline)
                    Spacer()
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            Color.secondary.opacity(0.35),
                            style: StrokeStyle(lineWidth: 1.5, dash: [6])
                        )
                }
            }
            .buttonStyle(.plain)
            .transition(.opacity)
```

with:

```swift
            PhotoSourceButton(selection: $selectedEditPhotoItem, onCapture: { uncroppedEditImage = $0 }) {
                HStack(spacing: 10) {
                    Image(systemName: "photo.badge.plus")
                        .font(.title3)
                    Text("Add a photo")
                        .font(.subheadline)
                    Spacer()
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            Color.secondary.opacity(0.35),
                            style: StrokeStyle(lineWidth: 1.5, dash: [6])
                        )
                }
            }
            .buttonStyle(.plain)
            .transition(.opacity)
```

- [ ] **Step 4: Replace `loadAndUploadEditImage(_:)` with a load step + a crop-confirm upload step**

In `PostDetailView+Logic.swift`, replace:

```swift
    func loadAndUploadEditImage(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        guard let rawData = try? await item.loadTransferable(type: Data.self),
              UIImage(data: rawData) != nil else { return }
        selectedEditPhotoData = rawData
        editImageUploadFailed = false
        guard let userID = store.currentUserID else { return }
        isUploadingEditImage = true
        defer { isUploadingEditImage = false }
        if let result = await ImageUploader.upload(input: .rawData(rawData), type: .postPhoto, userID: userID) {
            uploadedEditImageUrl = result.url
            uploadedEditAspectRatio = result.aspectRatio
            draftImageUrl = nil
        } else {
            // Drop the failed preview so what's on screen matches what Save keeps
            // (the post's previous image, if any).
            selectedEditPhotoData = nil
            selectedEditPhotoItem = nil
            editImageUploadFailed = true
        }
    }
```

with:

```swift
    func loadEditImage(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        guard let rawData = try? await item.loadTransferable(type: Data.self),
              let uiImage = UIImage(data: rawData) else { return }
        uncroppedEditImage = uiImage
    }

    func uploadCroppedEditImage(_ image: UIImage) async {
        selectedEditPhotoData = image.jpegData(compressionQuality: 0.85)
        editImageUploadFailed = false
        guard let userID = store.currentUserID else { return }
        isUploadingEditImage = true
        defer { isUploadingEditImage = false }
        if let result = await ImageUploader.upload(input: .uiImage(image), type: .postPhoto, userID: userID) {
            uploadedEditImageUrl = result.url
            uploadedEditAspectRatio = result.aspectRatio
            draftImageUrl = nil
        } else {
            // Drop the failed preview so what's on screen matches what Save keeps
            // (the post's previous image, if any).
            selectedEditPhotoData = nil
            selectedEditPhotoItem = nil
            editImageUploadFailed = true
        }
    }
```

`removeEditImage()` is unchanged — it already resets `selectedEditPhotoItem`/`selectedEditPhotoData`/`uploadedEditImageUrl`/etc., which still cover the new flow's state.

- [ ] **Step 5: Build**

Run: `xcodebuild -scheme "On Board" -destination "generic/platform=iOS Simulator" build 2>&1 | grep -E "error:|^\*\* BUILD (SUCCEEDED|FAILED)"`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Manual verification**

Open an existing post you authored, enter edit mode:
- "Add a photo" → library pick → crop → confirm → preview shows the cropped image.
- With an image already attached, "Change" → library pick → crop → confirm → preview updates.
- Save persists the new `uploadedEditImageUrl`; Cancel discards it (existing behavior, unchanged).

- [ ] **Step 7: Commit**

```bash
git add "On Board/Views/Post/PostDetailView.swift" "On Board/Views/Post/PostDetailView+Views.swift" "On Board/Views/Post/PostDetailView+Logic.swift"
git commit -m "feat: camera capture + crop for post-edit photos"
```

---

### Task 8: Wire camera into profile avatar editing

**Files:**
- Modify: `On Board/Views/Profile/ProfileEditContent.swift`
- Modify: `On Board/Views/Profile/ProfileView.swift`

**Interfaces:**
- Consumes: `PhotoSourceButton` (Task 2). No change to the existing circular `ImageCropView` flow — camera-captured images join it at the same point library-picked images already do.

- [ ] **Step 1: Replace the `PhotosPicker` in `avatarPicker`**

In `ProfileEditContent.swift`, replace:

```swift
        return PhotosPicker(selection: $draft.selectedPhotoItem, matching: .images) {
```

with:

```swift
        return PhotoSourceButton(selection: $draft.selectedPhotoItem, onCapture: onCameraCapture) {
```

Add a parameter to `ProfileEditContent` to carry the capture callback down from `ProfileView` (which owns `uncroppedImage`):

```swift
struct ProfileEditContent: View {
    let profile: Profile
    let namespace: Namespace.ID
    @Bindable var draft: ProfileDraft
    var onCameraCapture: (UIImage) -> Void
```

- [ ] **Step 2: Pass the callback from `ProfileView`**

In `ProfileView.swift`, find where `ProfileEditContent` is constructed (around line 109) and add the new argument:

```swift
                    ProfileEditContent(
                        profile: displayedProfile,
                        namespace: profileNamespace,
                        draft: draft,
                        onCameraCapture: { uncroppedImage = $0 }
                    )
```

- [ ] **Step 3: Build**

Run: `xcodebuild -scheme "On Board" -destination "generic/platform=iOS Simulator" build 2>&1 | grep -E "error:|^\*\* BUILD (SUCCEEDED|FAILED)"`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Manual verification**

Open your own profile, tap Edit, tap the avatar:
- "Choose from Library" → pick → circular crop sheet (existing `ImageCropView`) → confirm → avatar updates.
- "Take Photo" hidden in Simulator; confirm no crash.

- [ ] **Step 5: Commit**

```bash
git add "On Board/Views/Profile/ProfileEditContent.swift" "On Board/Views/Profile/ProfileView.swift"
git commit -m "feat: camera capture for profile avatar editing"
```

---

### Task 9: Wire camera into onboarding avatar step

**Files:**
- Modify: `On Board/Views/Onboarding/OnboardingProfileStepView.swift`

**Interfaces:**
- Consumes: `PhotoSourceButton` (Task 2). No change to the existing circular `ImageCropView` flow.

- [ ] **Step 1: Replace the `PhotosPicker`**

Replace:

```swift
                        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
```

with:

```swift
                        PhotoSourceButton(selection: $selectedPhotoItem, onCapture: { uncroppedImage = $0 }) {
```

- [ ] **Step 2: Build**

Run: `xcodebuild -scheme "On Board" -destination "generic/platform=iOS Simulator" build 2>&1 | grep -E "error:|^\*\* BUILD (SUCCEEDED|FAILED)"`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Manual verification**

Run onboarding to the profile step (fresh mock user), tap the avatar circle:
- "Choose from Library" → pick → crop → confirm → avatar preview updates, upload proceeds.
- "Take Photo" hidden in Simulator; confirm no crash.

- [ ] **Step 4: Commit**

```bash
git add "On Board/Views/Onboarding/OnboardingProfileStepView.swift"
git commit -m "feat: camera capture for onboarding avatar step"
```

---

### Task 10: Make display name optional end-to-end

**Files:**
- Modify: `On Board/Onboarding/SupabaseOnboardingService.swift`
- Modify: `On Board/Onboarding/MockOnboardingService.swift`
- Test: `On BoardTests/OnboardingProfileCompletionTests.swift`

**Background (already verified, no DB work needed):**
- `complete_onboarding_profile` (live RPC) does `normalized_name := btrim(p_display_name)` and writes it straight to `profiles.display_name` — it never rejects an empty string.
- `profiles.display_name` is `NOT NULL` but has no non-empty check; `''` satisfies `NOT NULL`.
- The UI already renders gracefully when `displayName` is empty: `ProfileReadContent.swift:118`, `ProfileView.swift:210`, `SettingsProfilePreview.swift:16` all fall back to `handle`.
- The only place that actually blocks an empty display name today is the client-side guard duplicated in both `OnboardingService` implementations — `OnboardingProfileStepView.swift`'s `canContinue` already treats it as optional and lets the user tap Continue with a blank name, which then throws.

- [ ] **Step 1: Write the failing test**

```swift
//
//  OnboardingProfileCompletionTests.swift
//  On BoardTests
//
//  Display name is optional — OnboardingProfileStepView.canContinue already
//  allows an empty name through, so the service layer must accept one too.
//  Pins the fix for the case where the RPC/mock still guarded against it.
//

import Foundation
import Testing
@testable import On_Board

@MainActor
struct OnboardingProfileCompletionTests {

    private func freshUser() -> (UUID, UserDefaults) {
        let userID = UUID()
        let suiteName = "OnboardingProfileCompletionTests.\(userID.uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let session = AuthSession(userId: userID, accessToken: "t", refreshToken: "r")
        defaults.set(try! JSONEncoder().encode(session), forKey: "mock.auth.session")
        return (userID, defaults)
    }

    @Test func completeProfileAcceptsEmptyDisplayName() async throws {
        let (_, defaults) = freshUser()
        let service = MockOnboardingService(defaults: defaults)
        let step = try await service.completeProfile(displayName: "", bio: nil, avatarUrl: nil)
        #expect(step == .schoolVerify)
    }

    @Test func completeProfileAcceptsWhitespaceOnlyDisplayName() async throws {
        let (_, defaults) = freshUser()
        let service = MockOnboardingService(defaults: defaults)
        let step = try await service.completeProfile(displayName: "   ", bio: nil, avatarUrl: nil)
        #expect(step == .schoolVerify)
    }
}
```

Check the exact `AuthSession` initializer signature in `On Board/Models/AuthSession.swift` (or wherever it's defined) before finalizing this test — adjust the constructor call above to match if its parameter names/types differ; the mock's `currentUserID(from:)` only requires that `mock.auth.session` decode to a valid `AuthSession` with the right `userId`.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodebuild test -scheme "On Board" -destination "platform=iOS Simulator,name=iPhone 16 Pro,OS=18.5" -only-testing "On BoardTests/OnboardingProfileCompletionTests" -parallel-testing-enabled NO`
Expected: FAIL — both throw `OnboardingError.profileIncomplete`.

- [ ] **Step 3: Remove the guard in `MockOnboardingService`**

In `MockOnboardingService.swift`, replace:

```swift
    func completeProfile(displayName: String, bio: String?, avatarUrl: String?) async throws -> OnboardingStep {
        try await Task.sleep(for: .milliseconds(180))
        guard let userID = MockOnboardingService.currentUserID(from: defaults) else {
            throw OnboardingError.notAuthenticated
        }

        let normalizedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else {
            throw OnboardingError.profileIncomplete
        }

        var status = loadStatus(for: userID)
```

with:

```swift
    func completeProfile(displayName: String, bio: String?, avatarUrl: String?) async throws -> OnboardingStep {
        try await Task.sleep(for: .milliseconds(180))
        guard let userID = MockOnboardingService.currentUserID(from: defaults) else {
            throw OnboardingError.notAuthenticated
        }

        let normalizedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)

        var status = loadStatus(for: userID)
```

- [ ] **Step 4: Remove the matching guard in `SupabaseOnboardingService`**

In `SupabaseOnboardingService.swift`, replace:

```swift
    func completeProfile(displayName: String, bio: String?, avatarUrl: String?) async throws -> OnboardingStep {
        let normalizedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else {
            throw OnboardingError.profileIncomplete
        }

        struct Params: Encodable {
```

with:

```swift
    func completeProfile(displayName: String, bio: String?, avatarUrl: String?) async throws -> OnboardingStep {
        let normalizedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)

        struct Params: Encodable {
```

`OnboardingError.profileIncomplete` and its `PresentableAlertError` case (`PresentableAlertError.swift:158`) can stay defined even though nothing throws it anymore — leave them; removing an enum case that's part of a shared error type on spec is out of scope here and low-value churn.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `xcodebuild test -scheme "On Board" -destination "platform=iOS Simulator,name=iPhone 16 Pro,OS=18.5" -only-testing "On BoardTests/OnboardingProfileCompletionTests" -parallel-testing-enabled NO`
Expected: PASS (both tests)

- [ ] **Step 6: Commit**

```bash
git add "On Board/Onboarding/SupabaseOnboardingService.swift" "On Board/Onboarding/MockOnboardingService.swift" "On BoardTests/OnboardingProfileCompletionTests.swift"
git commit -m "fix: make display name genuinely optional during onboarding"
```

---

### Task 11: Full-suite verification pass

**Files:** none (verification only)

- [ ] **Step 1: Full build**

Run: `xcodebuild -scheme "On Board" -destination "generic/platform=iOS Simulator" build 2>&1 | grep -E "error:|^\*\* BUILD (SUCCEEDED|FAILED)"`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 2: Full test suite**

Run: `xcodebuild test -scheme "On Board" -destination "platform=iOS Simulator,name=iPhone 16 Pro,OS=18.5" -parallel-testing-enabled NO`
Expected: all tests pass, including the new `PostCropGeometryTests`, `ImageProcessorTests`, `OnboardingProfileCompletionTests`.

- [ ] **Step 3: Manual pass across all four photo-entry sites in Simulator**

Confirm for each of: profile avatar edit, onboarding avatar step, new post, post edit —
- "Take Photo" does not appear (no Simulator camera) and nothing crashes when the dialog opens.
- "Choose from Library" still works end-to-end (pick → crop → upload → preview updates).
- Onboarding: completing the profile step with an empty display name advances to school verification instead of erroring.

- [ ] **Step 4: Flag remaining device-only verification**

Note explicitly to whoever picks this up next: the camera-capture path itself (`CameraCaptureView`, the "Take Photo" branch of `PhotoSourceButton`) has not been exercised on real hardware by this plan's steps, since the Simulator has no camera. Verify on a physical device before shipping: permission prompt text, capture → crop → upload for all four sites, and that denying camera access doesn't strand the user (the confirmation dialog still offers "Choose from Library").
