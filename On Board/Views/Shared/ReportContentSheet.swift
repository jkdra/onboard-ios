//
//  ReportContentSheet.swift
//  On Board
//
//  Native report flow for posts, comments, and profiles. Presented as a
//  sheet from the target's ellipsis menu; submits through the
//  `report_content` RPC via BoardStore. On success the reported content is
//  hidden for this user immediately (server RLS keeps it hidden).
//

import SwiftUI

struct ReportContentSheet: View {
    let target: ReportTarget
    /// Called after a successful submission (sheet dismisses itself first).
    var onReported: (() -> Void)?

    @Environment(BoardStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var reason: ReportReason?
    @State private var details = ""
    @State private var isSubmitting = false
    @State private var alertError: PresentableAlertError?

    private let detailsLimit = 500

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label(target.summary, systemImage: targetSymbol)
                        .fontStyle(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                } footer: {
                    Text(footerText)
                        .fontStyle(.footnote)
                }

                Section {
                    Picker(selection: $reason) {
                        Text("Choose a reason").tag(ReportReason?.none)
                        ForEach(ReportReason.allCases) { reason in
                            Text(reason.label).tag(ReportReason?.some(reason))
                        }
                    } label: {
                        Text("Reason").fontStyle(.body)
                    }
                    .pickerStyle(.navigationLink)
                } header: {
                    Text("Why are you reporting this?")
                        .fontStyle(.subheadline)
                }

                Section {
                    TextField("Anything else we should know?", text: $details, axis: .vertical)
                        .fontStyle(.body)
                        .keyboardType(.default)
                        .textInputAutocapitalization(.sentences)
                        .lineLimit(3...6)
                    if details.count >= Int(Double(detailsLimit) * 0.8) {
                        Text("\(details.count)/\(detailsLimit)")
                            .fontStyle(.caption2)
                            .foregroundStyle(details.count > detailsLimit ? Color.red : Color.orange)
                            .monospacedDigit()
                    }
                } header: {
                    Text("Details (optional)")
                        .fontStyle(.subheadline)
                }

                Section {
                    Button {
                        Task { await submit() }
                    } label: {
                        LoadingButtonLabel("Submit Report", systemImage: "flag.fill", isLoading: isSubmitting)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.boardPrimary)
                    .tint(.primary)
                    .disabled(reason == nil || isSubmitting || details.count > detailsLimit)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
            }
            .navigationTitle("Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Label("Cancel", systemImage: "xmark").fontWeight(.semibold) }
                        .disabled(isSubmitting)
                }
            }
            .interactiveDismissDisabled(isSubmitting)
            .keyboardDoneToolbar()
            .scrollDismissesKeyboard(.interactively)
            .presentableErrorAlert(error: $alertError)
        }
        .presentationDetents([.medium, .large])
    }

    private var targetSymbol: String {
        switch target {
        case .post: "doc.text"
        case .comment: "text.bubble"
        case .profile: "person.crop.circle"
        }
    }

    private var footerText: String {
        switch target {
        case .post, .comment:
            "Reported content is hidden for you right away and reviewed by the On Board team."
        case .profile:
            "Reported profiles are reviewed by the On Board team. To stop seeing this person's posts and comments, block them."
        }
    }

    private func submit() async {
        guard let reason else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let trimmedDetails = details.trimmed
            try await store.report(
                target: target,
                reason: reason,
                details: trimmedDetails.isEmpty ? nil : trimmedDetails
            )
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
            onReported?()
        } catch {
            alertError = store.presentableModerationError(error)
        }
    }
}

#Preview {
    ReportContentSheet(target: .post(Post.samples[0]))
        .environment(BoardStore.sampleBoard(currentUserID: SampleProfileID.maya))
}
