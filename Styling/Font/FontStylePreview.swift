//
//  FontStylePreview.swift
//  demonstrate
//
//  Created by Jawad Khadra on 1/13/25.
//

import SwiftUI

struct FontStylePreview: View {
    var body: some View {
        ScrollView(.horizontal) {
            HStack {
                VStack (alignment: .leading) {
                    Text("Large Title")
                        .font(.largeTitle)
                    Text("Title")
                        .font(.title)
                    Text("Title 2")
                        .font(.title2)
                    Text("Title 3")
                        .font(.title3)
                    Text("Healine")
                        .font(.headline)
                    Text("Body")
                        .font(.body)
                    Text("Callout")
                        .font(.callout)
                    Text("Subheadline")
                        .font(.subheadline)
                    Text("Footnote")
                        .font(.footnote)
                    Text("Caption")
                        .font(.caption)
                    Text("Caption 2")
                        .font(.caption2)
                }
                VStack (alignment: .leading){
                    Text("Large Title")
                        .fontStyle(.largeTitle)
                    Text("Title")
                        .fontStyle(.title)
                    Text("Title 2")
                        .fontStyle(.title2)
                    Text("Title 3")
                        .fontStyle(.title3)
                    Text("Healine")
                        .fontStyle(.headline)
                    Text("Body")
                        .fontStyle(.body)
                    Text("Callout")
                        .fontStyle(.callout)
                    Text("Subheadline")
                        .fontStyle(.subheadline)
                    Text("Footnote")
                        .fontStyle(.footnote)
                    Text("Caption")
                        .fontStyle(.caption)
                    Text("Caption 2")
                        .fontStyle(.caption2)
                }
            }
        }
    }
}

#Preview {
    FontStylePreview()
}
