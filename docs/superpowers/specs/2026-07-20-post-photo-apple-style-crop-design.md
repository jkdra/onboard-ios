# Post Photo Apple-Style Crop Design

## Goal

Make the post-photo cropper behave like Photos: users resize a crop selection, pan and zoom the underlying image, and after a brief pause the selected source region smoothly recenters and expands without changing the eventual output.

## Interaction model

- Dragging inside the selection pans the image; pinching zooms the image.
- Corner and (in Free mode) edge handles resize the selection.
- The transformed image always covers the selection; pan cannot expose empty space.
- One and a half seconds after an interaction ends, the selected normalized source region is mapped to the largest centered frame that fits in the image viewport. The image transform is adjusted at the same time, preserving the selected pixels.
- Any fresh interaction, aspect-ratio change, undo, redo, revert, layout change, cancel, or confirmation cancels a pending settle.
- The crop output's shorter source-image dimension cannot fall below 640 pixels when the source supports it.

## Architecture

`PostCropGeometry` owns the pure coordinate conversions and constraints. `PostImageCropView` owns gesture state, animation, delayed-settle task scheduling, history, and UIKit rendering. The base image remains fit to the viewport; a uniform scale and offset derive its effective display rect. The visible crop rect plus that effective rect maps to a normalized source crop, which is the canonical output representation.

## Rendering and verification

Confirmation converts the normalized source crop to pixels before rendering, so it remains correct after panning, zooming, or automatic recentering. Swift Testing covers transform geometry: effective display rect, coverage clamp, normalized/pixel mapping, and canonical recenter layout. Build and the full non-parallel test suite verify the SwiftUI integration.
