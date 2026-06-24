//
//  BoardStore.swift
//  On Board
//
//  In-memory session cache for the board UI. Supabase is the source of truth;
//  this type holds fetched data, the current user's reactions/votes, and
//  optimistic updates while mutations are in flight.
//
//  Preview/offline fixtures live in `BoardStore+Preview.swift`.
//  Mutations and social interactions live in `BoardStore+Interactions.swift`.
//

import Foundation
import Observation

@Observable
@MainActor
final class BoardStore {
    // MARK: - Session cache (from network or preview fixtures)

    var posts: [Post] = []
    var profiles: [Profile] = []
    var boardWeeks: [BoardWeek] = []
    var activeBoardWeek: BoardWeek?
    /// The board the user is currently viewing. Set from the active week on refresh.
    var currentBoard: Board?
    var currentUserID: UUID?
    var userReactions: [UUID: Reaction] = [:]
    var userCommentVotes: [UUID: CommentVote] = [:]
    private(set) var isLoading = false
    private(set) var accessibleBoards: [Board] = []
    var loadError: String?

    // MARK: - Internals

    var boardService: (any BoardService)?
    private var profileIndex = ProfileIndex(profiles: [])
    private var postsByWeek: [UUID: [Post]] = [:]
    private var postsByID: [UUID: Post] = [:]
    private var boardWeeksByID: [UUID: BoardWeek] = [:]
    private(set) var archivedWeeks: [BoardWeek] = []
    var commentsByPostID: [UUID: [Comment]] = [:]
    private var cachedFeedItemsByWeek: [UUID: [FeedItem]] = [:]
    private var feedItemsCacheKeys: [UUID: FeedItemsCacheKey] = [:]
    private var refreshTask: Task<Void, Never>?
    var reactionRealtimeListener: ReactionRealtimeListener?

    // MARK: - Archive LRU

    private static let maxCachedArchiveWeeks = 3
    private var cachedArchiveWeekIDs: [UUID] = []

    private struct FeedItemsCacheKey: Equatable {
        let postSignatures: [String]
        let canInteract: Bool
    }

    /// True when a Supabase client is configured for this session.
    var isLive: Bool { boardService != nil }

    var currentBoardId: UUID? {
        currentBoard?.id ?? activeBoardWeek?.boardId
    }

    init(boardService: (any BoardService)? = nil) {
        self.boardService = boardService
    }

    /// Convenience initializer for tests and previews.
    init(
        posts: [Post],
        profiles: [Profile],
        currentUserID: UUID? = nil,
        activeBoardWeek: BoardWeek? = nil,
        boardWeeks: [BoardWeek] = [],
        currentBoard: Board? = nil,
        boardService: (any BoardService)? = nil
    ) {
        self.posts = posts
        self.profiles = profiles
        self.currentUserID = currentUserID
        self.activeBoardWeek = activeBoardWeek
        self.boardWeeks = boardWeeks
        self.currentBoard = currentBoard
        self.boardService = boardService
        for post in posts where !post.comments.isEmpty {
            commentsByPostID[post.id] = post.comments
        }
        self.posts = posts.map(stripForFeed)
        rebuildCaches()
    }

    // MARK: - Configuration

    func configure(configuration: AppConfiguration) {
        boardService = BoardServiceFactory.make(configuration: configuration)
        if boardService == nil {
            loadError = nil
        }
    }

    func setBoard(id: UUID, name: String?) {
        currentBoard = Board(id: id, name: name ?? currentBoard?.name ?? "On Board")
    }

    func clearLoadError() {
        loadError = nil
    }

    /// Seeds local fixtures for Xcode previews only — not used in production flows.
    func loadOfflinePreviewData() {
        guard !isLive, activeBoardWeek == nil else { return }

        posts = Post.samples
        profiles = Profile.samples

        for post in posts where !post.comments.isEmpty {
            commentsByPostID[post.id] = post.comments
        }

        let weekStart = BoardSchedule.startOfWeek(containing: .now)
        let nextWeekStart = Calendar.current.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart.addingTimeInterval(86_400 * 7)
        let week = BoardWeek(
            id: SampleBoardWeekID.active,
            boardId: SampleBoardID.main,
            startsAt: weekStart,
            endsAt: nextWeekStart,
            status: .active
        )
        currentBoard = Board(id: SampleBoardID.main, name: "On Board")
        activeBoardWeek = week
        boardWeeks = [week]
        posts = posts.map { stripForFeed($0.assigning(boardWeekId: week.id, isReadOnly: false)) }
        rebuildCaches()
    }

    func resetForSignOut() {
        posts = []
        profiles = []
        boardWeeks = []
        activeBoardWeek = nil
        currentBoard = nil
        accessibleBoards = []
        currentUserID = nil
        userReactions = [:]
        userCommentVotes = [:]
        commentsByPostID = [:]
        cachedArchiveWeekIDs = []
        clearFeedItemsCache()
        loadError = nil
        Task { await stopReactionRealtime() }
        rebuildCaches()
    }

    // MARK: - Network refresh

    func refreshAccessibleBoards(for userID: UUID) async {
        guard let boardService else { return }
        do {
            accessibleBoards = try await boardService.listAccessibleBoards(for: userID)
        } catch {
            // Non-critical — switcher falls back to currentBoard
        }
    }

    func refresh(for userID: UUID?) async {
        guard let boardService, let userID else { return }

        if let refreshTask {
            await refreshTask.value
            return
        }

        let boardID = currentBoardId ?? SampleBoardID.main
        let hasCachedFeed = activeBoardWeek != nil && !posts.isEmpty

        let task = Task { @MainActor in
            if !hasCachedFeed {
                isLoading = true
            }
            loadError = nil
            defer { isLoading = false }

            do {
                async let snapshot = boardService.loadActiveBoard(boardID: boardID, for: userID)
                async let archivedWeeks = boardService.listArchivedWeeks(
                    boardID: boardID,
                    limit: 52,
                    offset: 0
                )
                apply(try await snapshot, incomingArchivedWeeks: try await archivedWeeks)
                await refreshAccessibleBoards(for: userID)
            } catch {
                loadError = Self.mapLoadError(error)
            }
        }

        refreshTask = task
        await task.value
        refreshTask = nil
    }

    func loadArchivedWeek(_ week: BoardWeek, for userID: UUID?) async {
        guard let boardService, let userID else { return }
        guard week.boardId == currentBoardId else { return }

        if cachedArchiveWeekIDs.contains(week.id) {
            cachedArchiveWeekIDs.removeAll { $0 == week.id }
            cachedArchiveWeekIDs.append(week.id)
            Task { await validateArchiveWeek(week, for: userID) }
            return
        }

        do {
            let loaded = try await boardService.fetchPosts(forWeek: week.id, userID: userID)
            mergeWeekPosts(loaded.posts, reactions: loaded.userReactions)
            cachedArchiveWeekIDs.append(week.id)
            evictOldArchiveWeeksIfNeeded()
        } catch {
            loadError = Self.mapLoadError(error)
        }
    }

    private func evictOldArchiveWeeksIfNeeded() {
        while cachedArchiveWeekIDs.count > Self.maxCachedArchiveWeeks {
            evictArchiveWeekPosts(weekID: cachedArchiveWeekIDs.removeFirst())
        }
    }

    private func evictArchiveWeekPosts(weekID: UUID) {
        guard let weekPosts = postsByWeek[weekID] else { return }
        let evictedIDs = Set(weekPosts.map(\.id))
        posts.removeAll { evictedIDs.contains($0.id) }
        for id in evictedIDs {
            commentsByPostID.removeValue(forKey: id)
            userReactions.removeValue(forKey: id)
        }
        rebuildCaches()
    }

    private func validateArchiveWeek(_ week: BoardWeek, for userID: UUID) async {
        guard let boardService else { return }
        do {
            let loaded = try await boardService.fetchPosts(forWeek: week.id, userID: userID)
            let cachedIDs = Set((postsByWeek[week.id] ?? []).map(\.id))
            let loadedIDs = Set(loaded.posts.map(\.id))
            guard cachedIDs != loadedIDs else { return }
            let staleIDs = cachedIDs.subtracting(loadedIDs)
            if !staleIDs.isEmpty {
                posts.removeAll { staleIDs.contains($0.id) }
            }
            mergeWeekPosts(loaded.posts, reactions: loaded.userReactions)
        } catch {
            // Keep stale cache on network error
        }
    }

    func loadComments(for postID: UUID) async {
        guard let boardService else { return }
        guard posts.contains(where: { $0.id == postID }) else { return }

        do {
            let thread = try await boardService.fetchComments(for: postID)
            commentsByPostID[postID] = thread.comments
            for (commentID, vote) in thread.userVotes {
                userCommentVotes[commentID] = vote
            }
        } catch {
            loadError = Self.mapLoadError(error)
        }
    }

    func comments(for postID: UUID) -> [Comment] {
        commentsByPostID[postID] ?? []
    }

    /// Feed-safe post lookup — O(1) via postsByID index.
    func feedPost(id: UUID) -> Post? {
        postsByID[id]
    }

    // MARK: - Feed composition

    func posts(for week: BoardWeek) -> [Post] {
        postsByWeek[week.id] ?? []
    }

    func feedItems(for week: BoardWeek) -> [FeedItem] {
        let weekPosts = posts(for: week)
        let cacheKey = FeedItemsCacheKey(
            postSignatures: weekPosts.map { "\($0.id.uuidString)-\($0.tone.rawValue)" },
            canInteract: canInteract(with: week)
        )

        if feedItemsCacheKeys[week.id] == cacheKey,
           let cached = cachedFeedItemsByWeek[week.id] {
            return cached
        }

        var items: [FeedItem] = [.countdown(week: week, isArchived: week.isReadOnly)]
        if canInteract(with: week) {
            items.append(.newPost)
        }
        items += weekPosts.map { .post(id: $0.id, tone: $0.tone) }

        cachedFeedItemsByWeek[week.id] = items
        feedItemsCacheKeys[week.id] = cacheKey
        return items
    }

    var feedItems: [FeedItem] {
        guard let activeBoardWeek else { return [] }
        return feedItems(for: activeBoardWeek)
    }

    var canInteractWithBoard: Bool {
        guard let activeBoardWeek else { return false }
        return canInteract(with: activeBoardWeek)
    }

    func canInteract(with week: BoardWeek) -> Bool {
        week.status == .active
            && week.id == activeBoardWeek?.id
            && week.boardId == currentBoardId
    }

    func canInteract(with post: Post) -> Bool {
        canInteractWithBoard && !post.isReadOnly
    }

    // MARK: - Lookups

    var currentUser: Profile? {
        guard let currentUserID else { return nil }
        return profile(id: currentUserID)
    }

    func setCurrentUser(id: UUID) {
        currentUserID = id
    }

    func clearCurrentUser() {
        currentUserID = nil
    }

    func post(with id: UUID) -> Post? {
        guard var post = feedPost(id: id) else { return nil }
        post.comments = comments(for: id)
        return post
    }

    func boardWeek(for id: UUID) -> BoardWeek? {
        boardWeeksByID[id]
    }

    func profile(id: UUID) -> Profile? {
        profileIndex.profile(id: id)
    }

    func profile(handle: String) -> Profile? {
        profileIndex.profile(handle: handle)
    }

    func profile(forAuthor handle: String) -> Profile {
        profile(handle: handle) ?? Profile(handle: handle, displayName: handle)
    }

    func canEdit(post: Post) -> Bool {
        isOwned(by: post.authorId, authorHandle: post.author)
    }

    func canEdit(comment: Comment) -> Bool {
        isOwned(by: comment.authorId, authorHandle: comment.author)
    }

    func canEdit(profile: Profile) -> Bool {
        guard let currentUserID else { return false }
        return profile.id == currentUserID
    }

    // MARK: - Internal cache updates

    func apply(_ snapshot: BoardSnapshot, incomingArchivedWeeks: [BoardWeek] = []) {
        let priorPosts = posts
        let priorByID = Dictionary(uniqueKeysWithValues: priorPosts.map { ($0.id, $0) })
        let activeWeekID = snapshot.week.id
        let incomingIDs = Set(snapshot.posts.map(\.id))

        activeBoardWeek = snapshot.week
        currentBoard = Board(id: snapshot.week.boardId, name: currentBoard?.name ?? "On Board")
        boardWeeks = [snapshot.week] + incomingArchivedWeeks

        posts = snapshot.posts.map(stripForFeed)

        posts.append(contentsOf: priorPosts.filter { post in
            guard let weekID = post.boardWeekId else { return false }
            return weekID != activeWeekID && !incomingIDs.contains(post.id)
        }.map(stripForFeed))

        for (id, existing) in priorByID where !existing.comments.isEmpty {
            commentsByPostID[id] = existing.comments
        }

        let validPostIDs = Set(posts.map(\.id))
        commentsByPostID = commentsByPostID.filter { validPostIDs.contains($0.key) }

        profiles = snapshot.profiles
        userReactions = snapshot.userReactions
        let validWeekIDs = Set(boardWeeks.map(\.id))
        cachedArchiveWeekIDs = cachedArchiveWeekIDs.filter { validWeekIDs.contains($0) }
        rebuildCaches()
        restartReactionRealtime()
    }

    func mergeWeekPosts(_ loadedPosts: [Post], reactions: [UUID: Reaction]) {
        let existingIDs = Set(posts.map(\.id))
        posts.append(contentsOf: loadedPosts.filter { !existingIDs.contains($0.id) }.map(stripForFeed))
        userReactions.merge(reactions) { _, new in new }
        rebuildCaches()
    }

    func replacePost(at index: Int, with post: Post) {
        let feedPost = stripForFeed(post)
        posts[index] = feedPost
        patchPostInWeekCache(feedPost)
    }

    func insertPost(_ post: Post, at index: Int = 0) {
        posts.insert(stripForFeed(post), at: index)
        rebuildCaches()
    }

    func rebuildCaches() {
        rebuildProfileIndex()
        rebuildPostsIndex()
        rebuildBoardWeeksIndex()
    }

    func isOwned(by authorId: UUID?, authorHandle: String) -> Bool {
        guard let currentUserID else { return false }
        if let authorId { return authorId == currentUserID }
        return currentUser?.handle.compare(authorHandle, options: .caseInsensitive) == .orderedSame
    }

    private func rebuildProfileIndex() {
        profileIndex = ProfileIndex(profiles: profiles)
    }

    private func rebuildBoardWeeksIndex() {
        boardWeeksByID = Dictionary(uniqueKeysWithValues: boardWeeks.map { ($0.id, $0) })
        guard let currentBoardId else { archivedWeeks = []; return }
        archivedWeeks = boardWeeks
            .filter { $0.boardId == currentBoardId && $0.status == .archived }
            .sorted { $0.startsAt > $1.startsAt }
    }

    private func rebuildPostsIndex() {
        clearFeedItemsCache()
        var byWeek: [UUID: [Post]] = [:]
        var byID: [UUID: Post] = [:]
        for post in posts {
            let feedPost = stripForFeed(post)
            byID[feedPost.id] = feedPost
            if let weekID = feedPost.boardWeekId {
                byWeek[weekID, default: []].append(feedPost)
            }
        }
        postsByWeek = byWeek
        postsByID = byID
    }

    func patchPostInWeekCache(_ post: Post) {
        let feedPost = stripForFeed(post)
        postsByID[feedPost.id] = feedPost
        guard let weekID = feedPost.boardWeekId,
              var weekPosts = postsByWeek[weekID],
              let index = weekPosts.firstIndex(where: { $0.id == feedPost.id }) else {
            return
        }
        weekPosts[index] = feedPost
        postsByWeek[weekID] = weekPosts
    }

    private func stripForFeed(_ post: Post) -> Post {
        var copy = post
        copy.comments = []
        return copy
    }

    private func clearFeedItemsCache() {
        cachedFeedItemsByWeek = [:]
        feedItemsCacheKeys = [:]
        postsByID = [:]
    }

    func removePost(id: UUID) {
        posts.removeAll { $0.id == id }
        commentsByPostID.removeValue(forKey: id)
        userReactions.removeValue(forKey: id)
        rebuildCaches()
    }

    func replaceComments(_ comments: [Comment], for postID: UUID) {
        commentsByPostID[postID] = comments
    }

    static func mapLoadError(_ error: Error) -> String {
        if let boardError = error as? BoardServiceError {
            return boardError.localizedDescription
        }
        if SessionErrorClassifier.isSessionExpired(error) {
            return AuthError.sessionExpired.localizedDescription
        }
        return error.localizedDescription
    }

    @discardableResult
    func mutateComments(for postID: UUID, _ transform: (inout [Comment]) -> Bool) -> Bool {
        guard var thread = commentsByPostID[postID] else { return false }
        let changed = transform(&thread)
        if changed {
            commentsByPostID[postID] = thread
        }
        return changed
    }
}
