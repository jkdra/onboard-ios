//
//  PostGeometryID.swift
//  On Board
//

/// Typed matched-geometry id for the card-image ↔ viewer hero handoff. The
/// card anchor (`isSource: !showImageViewer`) and the viewer
/// (`isSource: isPresented`) must reference the same id — a typed case makes
/// that contract greppable instead of two magic strings.
enum PostGeometryID {
    case postImage
}
