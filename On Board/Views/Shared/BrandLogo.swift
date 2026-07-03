//
//  BrandLogo.swift
//  On Board
//
//  The On Board monogram (OBLogo vector asset), sized to a square. Template-rendered by
//  default so it adopts the foreground color and flips with light/dark; pass `.original`
//  for the full-color mark.
//

import SwiftUI

struct BrandLogo: View {
    var size: CGFloat
    var renderingMode: Image.TemplateRenderingMode = .template

    var body: some View {
        Image("OBLogo")
            .renderingMode(renderingMode)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .foregroundStyle(.primary)
    }
}
