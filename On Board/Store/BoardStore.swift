//
//  BoardStore.swift
//  On Board
//
//  In-memory session cache for the board UI. Supabase is the source of truth;
//  this type holds fetched data, the current user's reactions/votes, and
//  optimistic updates while mutations are in flight.
//
//  Preview/offline fixtures live in `BoardStore+Preview.swift`. Social
//  interactions are split by concern: `+Posts`, `+Comments`, `+Reactions`,
//  `+Moderation`, `+Profiles`. Network refresh/archive loading is in
//  `+Refresh`; ownership/interaction-gating lookups are in `+Lookups`.
//
//  This file keeps the caching dicts (postsByWeek, postsByID, profileIndex,
//  postProxies, the feed-items cache) and every method that touches them
//  directly, fully private — Swift extensions can't hold stored properties,
//  so splitting these out further would mean widening them past `private`
//  for a cluster of methods (rebuildCaches, apply, mergeWeekPosts,
//  feedItems(for:), profile(id:), etc.) that are genuinely this
//  interdependent. +Refresh's archive eviction reaches this state only
//  through cachedPostIDs(inWeek:)/removeProxies(for:), not directly.
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
    // Set from BoardStore+Refresh; not private(set) since that file needs to
    // write them too, but nothing outside BoardStore's own extensions should.
    var isLoading = false
    var accessibleBoards: [Board] = []
    var loadError: String?
    /// Users the current user has blocked. Server RLS is the source of truth
    /// (their content never arrives); this mirrors it for immediate UI state
    /// (Blocked Users settings, profile screens, optimistic removal).
    var blockedUserIDs: Set<UUID> = []
    var followedUserIDs: Set<UUID> = []

    // MARK: - Internals

    var boardService: (any BoardService)?
    // These caching dicts (and the rebuild/apply/merge methods that touch
    // them) all stay in *this* file, not split into an extension — Swift
    // extensions can't hold stored properties, so any method that moves to a
    // different file needs its backing state widened past `private`. These
    // dicts are read/written by a genuinely tangled cluster of methods
    // (rebuildCaches, apply, mergeWeekPosts, feedItems(for:), profile(id:),
    // etc.), so splitting them out would cost real encapsulation for no
    // functional gain — kept fully private instead.
    private var profileIndex = ProfileIndex(profiles: [])
    private var postsByWeek: [UUID: [Post]] = [:]
    private var postsByID: [UUID: Post] = [:]
    private(set) var archivedWeeks: [BoardWeek] = []
    var commentsByPostID: [UUID: [Comment]] = [:]
    private var cachedFeedItemsByWeek: [UUID: [FeedItem]] = [:]
    private var feedItemsCacheKeys: [UUID: FeedItemsCacheKey] = [:]
    // Refresh-in-flight bookkeeping — only BoardStore+Refresh.swift touches these.
    var refreshTask: Task<Void, Never>?
    var refreshTaskID: UUID?
    var refreshTaskBoardID: UUID?
    // Keyed per-post so only the reacted card re-renders, not the whole feed.
    private(set) var postProxies: [UUID: PostStateProxy] = [:]
    // One in-flight reaction sync per post. A new tap cancels the prior request
    // so its (now stale) rollback can't fire against already-moved state.
    @ObservationIgnored var reactionSyncTasks: [UUID: Task<Void, Never>] = [:]
    // Same guard for comment up/down votes, keyed per comment.
    @ObservationIgnored var commentVoteSyncTasks: [UUID: Task<Void, Never>] = [:]

    // MARK: - Archive LRU

    static let maxCachedArchiveWeeks = 3
    static let maxConnectivityRetries = 2
    // Only BoardStore+Refresh.swift touches this (archive LRU bookkeeping).
    var cachedArchiveWeekIDs: [UUID] = []
    // Prevents a tap-time prefetch and ArchivedWeekView's own .task from firing
    // two redundant fetches for the same week when they race.
    @ObservationIgnored var inFlightArchiveWeekIDs: Set<UUID> = []

    fileprivate struct FeedItemsCacheKey: Equatable {
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
        loadError = nil
        // Previously only cleared postsByID (as a side effect of
        // clearFeedItemsCache()) — postsByWeek, profileIndex, and archivedWeeks
        // were left stale from the prior session. All the source arrays above
        // are already empty, so rebuilding here is cheap and correctly zeroes
        // every derived index.
        rebuildCaches()
    }

    // MARK: - Feed-safe post lookup

    /// O(1) via postsByID index.
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

    // MARK: - Profile lookups

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
        // Only postsByWeek/postsByID need reindexing for the appended posts —
        // profiles and boardWeeks are untouched here, and proxies were just
        // updated incrementally above, so the full rebuildCaches() (which would
        // redo all of that plus rebuild every proxy again) is unneeded work on
        // every archive-week merge.
        rebuildPostsIndex()
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
        rebuildArchivedWeeks()
        rebuildPostProxies()
    }

    private func rebuildProfileIndex() {
        profileIndex = ProfileIndex(profiles: profiles)
    }

    private func rebuildArchivedWeeks() {
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

    // MARK: - Narrow accessors for BoardStore+Refresh's archive eviction
    //
    // Archive eviction (loading an old week, LRU-evicting a cached one) needs
    // to know which post IDs belong to a week and to drop their proxies, but
    // shouldn't reach into postsByWeek/postProxies directly — that would
    // force those dicts to widen past `private`. These two narrow, purpose-
    // built methods let BoardStore+Refresh.swift do both without the dicts
    // themselves ever leaving this file.

    func cachedPostIDs(inWeek weekID: UUID) -> Set<UUID> {
        Set((postsByWeek[weekID] ?? []).map(\.id))
    }

    func removeProxies(for ids: Set<UUID>) {
        postProxies = postProxies.filter { !ids.contains($0.key) }
    }

    private func stripForFeed(_ post: Post) -> Post {
        var copy = post
        copy.comments = []
        return copy
    }

    private func clearFeedItemsCache() {
        cachedFeedItemsByWeek = [:]
        feedItemsCacheKeys = [:]
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
}
