//
//  TagSelectionView.swift
//  On Board
//

import SwiftUI

struct TagSelectionView: View {
    @Environment(BoardStore.self) private var store
    @Binding var selectedTags: [String]
    @Environment(\.dismiss) private var dismiss
    
    @State private var query = ""
    @State private var searchResults: [Tag] = []
    
    var body: some View {
        NavigationStack {
            List {
                if !selectedTags.isEmpty {
                    Section {
                        ForEach(selectedTags, id: \.self) { tag in
                            HStack {
                                Text("#\(tag)")
                                Spacer()
                                Button {
                                    selectedTags.removeAll(where: { $0 == tag })
                                } label: {
                                    Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                                }
                            }
                        }
                    } header: {
                        Text("Selected Tags (\(selectedTags.count)/3)")
                    }
                }
                
                Section {
                    if !query.isEmpty {
                        let cleanTag = query.lowercased().replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression)
                        if !cleanTag.isEmpty && !selectedTags.contains(cleanTag) && selectedTags.count < 3 {
                            Button {
                                addTag(cleanTag)
                            } label: {
                                HStack {
                                    Text("Create \"#\(cleanTag)\"")
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: "plus.circle.fill").foregroundStyle(.primary)
                                }
                            }
                        }
                    }
                    
                    ForEach(searchResults) { tag in
                        if !selectedTags.contains(tag.name) {
                            Button {
                                addTag(tag.name)
                            } label: {
                                HStack {
                                    Text("#\(tag.name)")
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Text("\(tag.postCount) posts").foregroundStyle(.secondary).fontStyle(.caption)
                                    Image(systemName: "plus.circle.fill").foregroundStyle(.primary)
                                }
                            }
                            .disabled(selectedTags.count >= 3)
                        }
                    }
                } header: {
                    Text("Search Results")
                }
            }
            .searchable(text: $query, prompt: "Search or create tags...")
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .onChange(of: query) { _, newQuery in
                Task {
                    guard let service = store.boardService else { return }
                    searchResults = (try? await service.searchTags(query: newQuery)) ?? []
                }
            }
            .navigationTitle("Tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Label("Done", systemImage: "checkmark").fontWeight(.semibold) }
                }
            }
        }
    }
    
    private func addTag(_ tag: String) {
        if selectedTags.count < 3 && !selectedTags.contains(tag) {
            selectedTags.append(tag)
            query = ""
            searchResults = []
        }
    }
}

#Preview {
    TagSelectionView(selectedTags: .constant(["test_one", "test_2"]))
}
