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

// One instance per post. FeedGridCard observes proxy.post / proxy.reaction directly,
// so any mutation (reaction tap, realtime count update, tone change) only re-renders
// that specific card — not the whole feed.
@Observable
final class PostStateProxy {
    var post: Post
    var reaction: Reaction?
    init(post: Post, reaction: Reaction? = nil) {
        self.post = post
        self.reaction = reaction
    }
}

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
    /// Users the current user has blocked. Server RLS is the source of truth
    /// (their content never arrives); this mirrors it for immediate UI state
    /// (Blocked Users settings, profile screens, optimistic removal).
    var blockedUserIDs: Set<UUID> = []
    var followedUserIDs: Set<UUID> = []

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
    private var refreshTaskID: UUID?
    private var refreshTaskBoardID: UUID?
    var reactionRealtimeListener: ReactionRealtimeListener?
    // Keyed per-post so only the reacted card re-renders, not the whole feed.
    private(set) var postProxies: [UUID: PostStateProxy] = [:]
    // One in-flight reaction sync per post. A new tap cancels the prior request
    // so its (now stale) rollback can't fire against already-moved state.
    @ObservationIgnored var reactionSyncTasks: [UUID: Task<Void, Never>] = [:]
    // Same guard for comment up/down votes, keyed per comment.
    @ObservationIgnored var commentVoteSyncTasks: [UUID: Task<Void, Never>] = [:]

    // MARK: - Archive LRU

    private static let maxCachedArchiveWeeks = 3
    private static let maxConnectivityRetries = 2
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
        blockedUserIDs = []
        followedUserIDs = []
        postProxies = [:]
        commentsByPostID = [:]
        cachedArchiveWeekIDs = []
        clearFeedItemsCache()
        loadError = nil
        let listenerToStop = reactionRealtimeListener
        reactionRealtimeListener = nil
        Task { await listenerToStop?.stop() }
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

    func refreshFollowedUsers(for userID: UUID) async {
        guard let boardService else { return }
        do {
            followedUserIDs = try await boardService.fetchFollowedUserIDs()
        } catch {
            // Non-critical
        }
    }

    func refresh(for userID: UUID?) async {
        guard let boardService, let userID else { return }
        // Never fall back to the sample/dev board on live paths: no assigned
        // board means there is nothing to fetch yet (waitlisted user).
        guard let boardID = currentBoardId else { return }

        if let inFlight = refreshTask {
            if refreshTaskBoardID == boardID {
                await inFlight.value
                return
            }
            // The in-flight load is for a different board (user switched mid-load).
            // Supersede it: cancel, wait it out, then load the selected board.
            inFlight.cancel()
            await inFlight.value
        }

        // Only treat the cache as warm when it belongs to the board being fetched —
        // on a board switch the old board's feed must not suppress the loading state.
        let hasCachedFeed = activeBoardWeek?.boardId == boardID && !posts.isEmpty

        let task = Task { @MainActor in
            if !hasCachedFeed {
                isLoading = true
            }
            loadError = nil
            defer { isLoading = false }

            // A weak connection can drop a single request (e.g. a zero-byte response),
            // so retry transient connectivity failures a couple of times before
            // surfacing the "Couldn't load board" state.
            var attempt = 0
            while true {
                do {
                    async let snapshot = boardService.loadActiveBoard(boardID: boardID, for: userID)
                    async let archivedWeeks = boardService.listArchivedWeeks(
                        boardID: boardID,
                        limit: 52,
                        offset: 0
                    )
                    apply(try await snapshot, incomingArchivedWeeks: try await archivedWeeks)
                    await refreshAccessibleBoards(for: userID)
                    await refreshBlockedUsers(for: userID)
                    await refreshFollowedUsers(for: userID)
                    break
                } catch {
                    if Task.isCancelled { break }
                    attempt += 1
                    guard NetworkErrorClassifier.isConnectivityFailure(error),
                          attempt <= Self.maxConnectivityRetries else {
                        loadError = Self.mapLoadError(error)
                        break
                    }
                    try? await Task.sleep(for: .milliseconds(400 * attempt))
                }
            }
        }

        let taskID = UUID()
        refreshTask = task
        refreshTaskID = taskID
        refreshTaskBoardID = boardID
        await task.value
        if refreshTaskID == taskID {
            refreshTask = nil
            refreshTaskID = nil
            refreshTaskBoardID = nil
        }
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
        postProxies = postProxies.filter { !evictedIDs.contains($0.key) }
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
        // Posting closes for the final hour before the board clears, so nobody can be
        // mid-compose when the weekly reset wipes the week. ContentView's 60s tick
        // re-reads feedItems, so the new-post entry disappears within a minute of the cutoff.
        let canPost = canInteract(with: week)
            && !BoardSchedule.isWithinFinalHour(weekEnd: week.endsAt)
        let cacheKey = FeedItemsCacheKey(
            postSignatures: weekPosts.map { "\($0.id.uuidString)-\($0.tone.rawValue)" },
            canInteract: canPost
        )

        if feedItemsCacheKeys[week.id] == cacheKey,
           let cached = cachedFeedItemsByWeek[week.id] {
            return cached
        }

        var items: [FeedItem] = [.countdown(week: week, isArchived: week.isReadOnly)]
        if canPost {
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

    var hasFeedPosts: Bool {
        feedItems.contains { if case .post = $0 { return true }; return false }
    }

    var currentBoardWeeks: [BoardWeek] {
        guard let boardID = currentBoardId else { return boardWeeks }
        return boardWeeks.filter { $0.boardId == boardID }
    }

    var clearingBannerText: String? {
        BoardSchedule.finalHourBannerText(weekEnd: activeBoardWeek?.endsAt)
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

    func profile(id: UUID) -> Profile? {
        profileIndex.profile(id: id)
    }

    func profile(handle: String) -> Profile? {
        profileIndex.profile(handle: handle)
    }

    func profile(forAuthor handle: String) -> Profile {
        profile(handle: handle) ?? Profile(handle: handle, displayName: handle)
    }

    func upsertProfile(_ profile: Profile) {
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
        } else {
            profiles.append(profile)
        }
        rebuildCaches()
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
        // A load that finished after the user switched boards must not clobber
        // the switch — drop the stale snapshot.
        if let currentBoardId, snapshot.week.boardId != currentBoardId { return }
        let priorPosts = posts
        let priorByID = Dictionary(priorPosts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
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
        let newPosts = loadedPosts.filter { !existingIDs.contains($0.id) }
        posts.append(contentsOf: newPosts.map(stripForFeed))
        userReactions.merge(reactions) { _, new in new }
        // Add proxies for newly merged posts in one dict assignment
        var updated = postProxies
        for post in newPosts where updated[post.id] == nil {
            let feedPost = stripForFeed(post)
            updated[feedPost.id] = PostStateProxy(post: feedPost, reaction: reactions[feedPost.id])
        }
        postProxies = updated
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
        rebuildPostProxies()
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
        // A week can transiently appear twice (e.g. it flips active→archived between
        // the two concurrent fetches in refresh) — never trap on the duplicate.
        boardWeeksByID = Dictionary(boardWeeks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
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
        postProxies[feedPost.id]?.post = feedPost
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

    static func mapLoadError(_ error: Error) -> String {
        if let boardError = error as? BoardServiceError {
            return boardError.localizedDescription
        }
        if SessionErrorClassifier.isSessionExpired(error) {
            return AuthError.sessionExpired.localizedDescription
        }
        if NetworkErrorClassifier.isConnectivityFailure(error) {
            return AuthError.networkUnavailable.localizedDescription
        }
        return error.localizedDescription
    }

    private func rebuildPostProxies() {
        var updated: [UUID: PostStateProxy] = [:]
        for post in posts {
            let feedPost = stripForFeed(post)
            if let existing = postProxies[feedPost.id] {
                existing.post = feedPost
                existing.reaction = userReactions[feedPost.id]
                updated[feedPost.id] = existing
            } else {
                updated[feedPost.id] = PostStateProxy(post: feedPost, reaction: userReactions[feedPost.id])
            }
        }
        postProxies = updated
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

    // MARK: - Notification Settings

    func fetchNotificationSettings() async throws -> NotificationSettings {
        guard let boardService, let currentUserID else { throw BoardServiceError.notAuthenticated }
        return try await boardService.fetchNotificationSettings(for: currentUserID)
    }

    func updateNotificationSettings(_ settings: NotificationSettings) async throws {
        guard let boardService, let currentUserID else { throw BoardServiceError.notAuthenticated }
        try await boardService.updateNotificationSettings(settings, for: currentUserID)
    }
}
