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
