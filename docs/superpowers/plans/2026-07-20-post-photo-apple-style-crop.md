# Post Photo Apple-Style Crop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Apple Photos-style pan, zoom, delayed recentering, and source-resolution-safe output to the rectangular post-photo cropper.

**Architecture:** The crop selection is represented by `cropRect`; the image is drawn from a fit-frame transformed with a scale and offset. `PostCropGeometry` converts between that display state and normalized image coordinates. A delayed task transforms the same normalized selection into a centered, maximum-size layout.

**Tech Stack:** Swift 6, SwiftUI, UIKit, Swift Testing, CoreGraphics.

## Global Constraints

- Preserve the existing iOS 18 deployment target and no-new-dependency policy.
- Keep the crop result at or above a 640px shorter source-image dimension whenever the source image permits it.
- Test new pure geometry before production implementation.

---

### Task 1: Complete and test transform geometry

**Files:** `On Board/Utilities/PostCropGeometry.swift`, `On BoardTests/PostCropGeometryTests.swift`

- [ ] Add failing tests for effective display rectangles, coverage clamping, normalized/pixel conversion, and canonical recenter layouts.
- [ ] Run the focused Swift Testing suite and observe each test fail for the intended missing behavior.
- [ ] Complete the pure geometry methods with the smallest correct implementation.
- [ ] Re-run the focused suite and confirm it passes.

### Task 2: Connect transform state to crop interactions and output

**Files:** `On Board/Views/Shared/PostImageCropView.swift`, `On BoardTests/PostCropGeometryTests.swift`

- [ ] Add failing transform-mapping tests before changing view behavior.
- [ ] Render the sharp and blurred image using one shared scale/offset transform.
- [ ] Make interior drag pan, magnify gesture zoom, and handle gestures resize the crop frame.
- [ ] Clamp transforms to cover the crop frame and calculate the 640px source-resolution floor from the effective image rect.
- [ ] Render confirmation from normalized source-image coordinates.

### Task 3: Add delayed recenter-and-enlarge behavior

**Files:** `On Board/Views/Shared/PostImageCropView.swift`

- [ ] Schedule a cancellable 1.5-second settle task when interactions end.
- [ ] Convert the current selection to normalized coordinates and animate it to `normalizedLayout`.
- [ ] Cancel pending settlement for every new interaction and all non-gesture state transitions.

### Task 4: Verify and commit

- [ ] Run `git diff --check` and inspect status.
- [ ] Run the complete non-parallel test suite.
- [ ] Build the app for the configured iPhone 16 Pro simulator.
- [ ] Commit the cropper, geometry, tests, design, and plan files together.
