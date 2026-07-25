//
//  PolicyView.swift
//  On Board
//
//  Native, in-app Terms / Privacy page. Fetches the canonical text from the
//  backend (`LegalService` → `get_legal_document` RPC) and renders the markdown
//  natively instead of loading the website in a web view. If the fetch fails
//  (offline, or a build with no Supabase configured), it offers the web page.
//

import SwiftUI

struct PolicyView: View {
    let type: LegalDocumentType

    @State private var phase: Phase = .loading
    @Environment(\.openURL) private var openURL

    private enum Phase: Equatable {
        case loading
        case loaded(LegalDocument)
        case failed
    }

    var body: some View {
        Group {
            switch phase {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loaded(let doc):
                loadedContent(doc)
            case .failed:
                failureState
            }
        }
        .background(Color(.systemBackground))
        .navigationTitle(type.title)
        .navigationBarTitleDisplayMode(.large)
        .task(id: type) { await load() }
    }

    private func loadedContent(_ doc: LegalDocument) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let effective = formattedEffectiveDate(doc.effectiveAt) {
                    Text("Effective \(effective)")
                        .fontStyle(.footnote)
                        .foregroundStyle(.secondary)
                }

                PolicyMarkdownView(markdown: doc.content)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .safeAreaPadding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
    }

    private var failureState: some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.slash")
                .fontStyle(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Couldn't load the \(type.title.lowercased())")
                .fontStyle(.headline)
                .multilineTextAlignment(.center)
            Text("Check your connection and try again, or open it in your browser.")
                .fontStyle(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                openURL(type.webURL)
            } label: {
                Label("Open in browser", systemImage: "safari")
            }
            .buttonStyle(.boardSecondary)
        }
        .safeAreaPadding(.horizontal)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func load() async {
        phase = .loading
        do {
            let doc = try await LegalService.fetch(type)
            phase = .loaded(doc)
        } catch {
            phase = .failed
        }
    }

    private func formattedEffectiveDate(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let isoFull = ISO8601DateFormatter()
        isoFull.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let iso = ISO8601DateFormatter()
        let date = isoFull.date(from: raw) ?? iso.date(from: raw)
        guard let date else { return nil }
        let out = DateFormatter()
        out.dateStyle = .long
        return out.string(from: date)
    }
}

/// Minimal, dependency-free markdown renderer for policy text: `## ` headings,
/// `- ` bullet lists, and paragraphs, with inline bold + links inside each.
struct PolicyMarkdownView: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let text):
                    inline(text)
                        .fontStyle(.title3)
                        .fontWeight(.bold)
                        .padding(.top, 6)
                case .paragraph(let text):
                    inline(text)
                        .fontStyle(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                case .bullets(let items):
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                            HStack(alignment: .top, spacing: 10) {
                                Text("•").fontStyle(.subheadline).foregroundStyle(.secondary)
                                inline(item)
                                    .fontStyle(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
            }
        }
    }

    /// Inline markdown (bold, links) within a single block.
    private func inline(_ string: String) -> Text {
        if let attr = try? AttributedString(
            markdown: string,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return Text(attr)
        }
        return Text(string)
    }

    private enum Block {
        case heading(String)
        case paragraph(String)
        case bullets([String])
    }

    private var blocks: [Block] {
        var result: [Block] = []
        let lines = markdown.components(separatedBy: "\n")
        var paragraph: [String] = []

        func flushParagraph() {
            if !paragraph.isEmpty {
                result.append(.paragraph(paragraph.joined(separator: " ")))
                paragraph = []
            }
        }

        var i = 0
        while i < lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                flushParagraph()
                i += 1
            } else if trimmed.hasPrefix("## ") {
                flushParagraph()
                result.append(.heading(String(trimmed.dropFirst(3))))
                i += 1
            } else if trimmed.hasPrefix("- ") {
                flushParagraph()
                var items: [String] = []
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    guard t.hasPrefix("- ") else { break }
                    items.append(String(t.dropFirst(2)))
                    i += 1
                }
                result.append(.bullets(items))
            } else {
                paragraph.append(trimmed)
                i += 1
            }
        }
        flushParagraph()
        return result
    }
}

#Preview {
    NavigationStack {
        PolicyView(type: .terms)
    }
}
