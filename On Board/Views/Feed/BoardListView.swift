//
//  BoardListView.swift
//  On Board
//
//  Root board-picker. Shows a persistent sidebar on iPad/Mac; collapses
//  to a full-screen stack on iPhone. Saves and restores the last-viewed
//  board so the app opens directly to it.
//

import SwiftUI
import NukeUI

struct BoardListView: View {
    @Environment(BoardStore.self) private var store
    @Environment(OnboardingStore.self) private var onboarding
    @AppStorage("appearance") private var appearance: AppearancePreference = .system

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var selectedBoardID: String?
    @State private var showSettings = false

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedBoardID) {
                if !listedBoards.isEmpty {
                    Section {
                        ForEach(listedBoards) { board in
                            boardRow(
                                id: board.id.uuidString,
                                name: board.name,
                                members: nil,
                                isJoined: true
                            )
                            .tag(board.id.uuidString)
                        }
                    }
                }
            }
            .navigationTitle("Your Boards")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: {
                        profileAvatar
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .fullScreenCover(isPresented: $showSettings) {
                SettingsView()
                    .environment(\.dynamicTypeSize, dynamicTypeSize)
            }
        } detail: {
            ContentView()
        }
        .preferredColorScheme(appearance.colorScheme)
        .onAppear {
            if selectedBoardID == nil, let board = store.currentBoard {
                selectedBoardID = board.id.uuidString
            }
        }
        .onChange(of: selectedBoardID) { _, newValue in
            guard let newValue,
                  let boardID = UUID(uuidString: newValue),
                  boardID != store.currentBoardId,
                  let board = listedBoards.first(where: { $0.id == boardID }) else { return }
            store.setBoard(id: board.id, name: board.name)
            Task { await store.refresh(for: store.currentUserID) }
        }
    }

    // MARK: - Board list

    private var listedBoards: [Board] {
        var boards = store.accessibleBoards
        if let current = store.currentBoard, !boards.contains(where: { $0.id == current.id }) {
            boards.insert(current, at: 0)
        }
        return boards
    }

    // MARK: - Profile avatar

    @ViewBuilder
    private var profileAvatar: some View {
        if let urlString = onboarding.status?.avatarUrl,
           let url = URL(string: urlString) {
            LazyImage(request: OnBoardImagePipeline.request(url: url, width: 30)) { state in
                if let image = state.image {
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: 30, height: 30)
                        .clipShape(Circle())
                } else {
                    Image(systemName: "person.circle")
                        .font(.title3)
                }
            }
            .frame(width: 30, height: 30)
        } else {
            Image(systemName: "person.circle")
                .font(.title3)
        }
    }

    // MARK: - Row

    private func boardRow(
        id: String,
        name: String,
        members: String?,
        isJoined: Bool
    ) -> some View {
        HStack(spacing: 8) {
            Text(name)
                .fontStyle(.subheadline)
                .foregroundStyle(.primary)

            Spacer(minLength: 12)

            if isJoined {
                if horizontalSizeClass == .compact {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.primary)
                        .font(.body)
                }
            } else if let members {
                HStack(spacing: 4) {
                     Image(systemName: "person.3.fill")
                        .font(.caption2)
                    Text(members)
                        .fontStyle(.caption)
                }
                .foregroundStyle(.secondary)

                Text("Join")
                    .fontStyle(.caption)
                    .foregroundStyle(Color.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.12), in: Capsule())
            }
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

#Preview {
    let auth = AuthStore(service: MockAuthService())
    let network = NetworkMonitor()
    BoardListView()
        .environment(BoardStore.previewBoard())
        .environment(auth)
        .environment(OnboardingStore(
            service: MockOnboardingService(),
            auth: auth,
            network: network
        ))
}
