//
//  BoardListView.swift
//  On Board
//
//  Root board-picker. Navigates into ContentView for the selected board.
//  Saves and restores the last-viewed board so the app opens directly to it.
//

import SwiftUI

struct BoardListView: View {
    @Environment(BoardStore.self) private var store
    @Environment(AuthStore.self) private var auth
    @Environment(OnboardingStore.self) private var onboarding
    @AppStorage("appearance") private var appearance: AppearancePreference = .system

    @AppStorage("lastViewedBoardID") private var lastViewedBoardID: String = ""
    @State private var path = NavigationPath()
    @State private var showSettings = false

    // Placeholder boards to demonstrate the multi-board concept
    private let discoveryBoards: [(name: String, members: String)] = [
        ("Stanford University",  "2.4k members"),
        ("MIT",                  "1.8k members"),
        ("Cornell University",   "3.1k members"),
    ]

    var body: some View {
        NavigationStack(path: $path) {
            List {
                // Active board
                if let board = store.currentBoard {
                    Section {
                        boardRow(
                            id: board.id.uuidString,
                            name: board.name,
                            detail: "Your active board",
                            icon: "building.2.fill",
                            isJoined: true
                        )
                    } header: {
                        Text("Your boards")
                            .fontStyle(.footnote)
                    }
                }

                // Discovery
                Section {
                    ForEach(discoveryBoards, id: \.name) { board in
                        boardRow(
                            id: board.name,        // placeholder ID
                            name: board.name,
                            detail: board.members,
                            icon: "building.2",
                            isJoined: false
                        )
                    }
                } header: {
                    Text("Discover")
                        .fontStyle(.footnote)
                }
            }
            .navigationTitle("Your Boards")
            .navigationDestination(for: String.self) { boardID in
                ContentView(navigationPath: $path)
                    .onAppear { lastViewedBoardID = boardID }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: {
                        profileAvatar
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
        }
        .preferredColorScheme(appearance.colorScheme)
        .onAppear {
            // Restore last-viewed board — skip the list and open directly
            if path.isEmpty,
               let board = store.currentBoard,
               lastViewedBoardID == board.id.uuidString {
                path.append(board.id.uuidString)
            }
        }
    }

    // MARK: - Profile avatar

    @ViewBuilder
    private var profileAvatar: some View {
        if let urlString = onboarding.status?.avatarUrl,
           let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: 30, height: 30)
                        .clipShape(Circle())
                default:
                    Image(systemName: "person.circle")
                        .font(.title3)
                }
            }
        } else {
            Image(systemName: "person.circle")
                .font(.title3)
        }
    }

    // MARK: - Row

    private func boardRow(
        id: String,
        name: String,
        detail: String,
        icon: String,
        isJoined: Bool
    ) -> some View {
        Button {
            if isJoined { path.append(id) }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(isJoined ? Color.accentColor : .secondary)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .fontStyle(.subheadline)
                        .foregroundStyle(.primary)
                    Text(detail)
                        .fontStyle(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isJoined {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                } else {
                    Text("Join")
                        .fontStyle(.caption)
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                }
            }
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
