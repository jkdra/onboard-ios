//
//  WebContentSheet.swift
//  On Board
//
//  Minimal in-app web viewer for external content (legal pages, etc.) so
//  tapping a link doesn't leave the app for Safari.
//

import SwiftUI
import WebKit

/// Identifies which document to load in `WebContentSheet`.
struct WebDocument: Identifiable {
    let title: String
    let url: URL
    var id: String { url.absoluteString }
}

private struct WebContentView: UIViewRepresentable {
    let url: URL
    @Binding var isLoading: Bool

    func makeCoordinator() -> Coordinator { Coordinator(isLoading: $isLoading) }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        @Binding var isLoading: Bool
        init(isLoading: Binding<Bool>) { _isLoading = isLoading }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            isLoading = true
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoading = false
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            isLoading = false
        }
    }
}

struct WebContentSheet: View {
    let document: WebDocument
    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            ZStack {
                WebContentView(url: document.url, isLoading: $isLoading)
                if isLoading {
                    ProgressView()
                }
            }
            .ignoresSafeArea()
            .navigationTitle(document.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Label("Close", systemImage: "xmark")
                    }
                }
            }
        }
    }
}

#Preview {
    Text("Base")
        .sheet(isPresented: .constant(true)) {
            WebContentSheet(document: WebDocument(title: "Privacy Policy", url: AppLinks.privacyPolicyURL))
        }
}
