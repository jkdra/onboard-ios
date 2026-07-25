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
                                        .accessibilityLabel("Remove #\(tag)")
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
                        // Suppress "Create #x" when an exact match already exists in the
                        // results — otherwise typing an existing tag shows both a redundant
                        // Create row and the real one. (Before the Tag decode fix this never
                        // mattered: searchResults was always empty, so only Create ever showed.)
                        let exactMatchExists = searchResults.contains { $0.name == cleanTag }
                        if !cleanTag.isEmpty && !selectedTags.contains(cleanTag) && selectedTags.count < 3 && !exactMatchExists {
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
                    Text(query.isEmpty ? "Popular Tags" : "Search Results")
                }
            }
            .searchable(text: $query, prompt: "Search or create tags...")
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            // Runs on appear (query == "" → the board's popular tags) and on every
            // keystroke; the id-change cancels the prior in-flight request.
            .task(id: query) {
                await refreshResults()
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
            // Reset to the popular-tags state. Don't clear searchResults — the
            // ForEach already filters out selected tags, so the rest of the list
            // stays put (and if query was non-empty, .task(id:) re-fetches).
            query = ""
        }
    }

    private func refreshResults() async {
        guard let service = store.boardService,
              let boardID = store.currentBoardId else { return }
        // Board-scoped: only this board's tags. Empty query → popular tags.
        searchResults = (try? await service.searchTags(query: query, boardID: boardID)) ?? []
    }
}

#Preview {
    TagSelectionView(selectedTags: .constant(["test_one", "test_2"]))
}
