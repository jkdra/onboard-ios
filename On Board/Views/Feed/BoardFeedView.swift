//
//  BoardFeedView.swift
//  On Board
//
//  Two-column masonry feed. All board items — countdown, new-post button, and
//  posts — share the same column grid so the countdown feels like part of the board.
//  Posts are distributed greedily to the shorter column based on estimated
//  card height (200pt base + image card height if the post has an image).
//

import SwiftUI

struct BoardFeedView: View {
    let items: [FeedItem]
    var onNewPost: (() -> Void)?
    var isResetting: Bool = false
    var originatingProfileID: UUID? = nil
    /// Plays the countdown card's one-time birthday greeting (feed only).
    var celebrateBirthday: Bool = false
    /// Fires as the (enabled) new-post card scrolls in/out of the visible region,
    /// so the feed can surface a bottom-bar compose button once it's off-screen.
    var onNewPostCardVisibilityChanged: ((Bool) -> Void)? = nil

    // Read from the environment rather than taken as a parameter: the zoom
    // destination lives in ContentView, so every card must register its source in
    // ContentView's namespace. See EnvironmentValues.cardNamespace.
    @Environment(\.cardNamespace) private var cardNamespace
    @Environment(BoardStore.self) private var store
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("rotationIntensity") private var rotationIntensity: Double = 0.6

    /// Per-item entrance tracking. A single "appeared" flag only animated the
    /// cards present at first render — anything fetched later (a refresh
    /// landing after onAppear, archive weeks) popped in with no animation.
    /// Each cell reveals itself on its own first appearance instead.
    @State private var revealedIDs: Set<String> = []
    /// The initial batch staggers by column index; later arrivals animate
    /// immediately (an index-based delay on a single late card reads as lag).
    @State private var initialIDs: Set<String> = []
    @State private var rotations: [String: Double] = [:]
    @State private var leftColumn: [FeedItem] = []
    @State private var rightColumn: [FeedItem] = []
    @State private var containerWidth: CGFloat = 0
    /// Which week the current items belong to, read off the countdown card. When it
    /// changes, the whole board is new content — see `onChange(of: items)`.
    @State private var lastSeenWeekID: UUID?

    /// Cards currently on screen, maintained via `onScrollVisibilityChange`. Drives
    /// both the header-card visibility callbacks and the reset take-down: only
    /// on-screen cards animate out; the rest are dropped instantly. Read live during
    /// render (not snapshotted in onChange) so the visible set is already correct in
    /// the same pass `isResetting` flips true — otherwise the cards are filtered out
    /// before the animation can run and just vanish.
    @State private var visibleIDs: Set<String> = []

    private let rowSpacing: CGFloat = 16

    // Outer 16pt padding ×2 + 12pt inter-column gap = 44pt of non-content width.
    private var columnWidth: CGFloat { max(0, (containerWidth - 44) / 2) }

    // MARK: - Body

    var body: some View {
        LazyVStack(spacing: 0) {
            if typeSize.isAccessibilitySize { accessibleStack }
            else { masonryGrid }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { newWidth in
            guard newWidth != containerWidth else { return }
            containerWidth = newWidth
            recomputeColumns()
        }
        .onAppear {
            seedRotationsIfNeeded()
            recomputeColumnsIfNeeded()
            if initialIDs.isEmpty {
                initialIDs = Set(items.map(\.id))
            }
            lastSeenWeekID = weekID(in: items)
        }
        .onChange(of: items) { _, newItems in
            seedRotationsForNewItems()
            recomputeColumns()
            // Weekly rollover: every cell is a fresh identity (post ids are new, the
            // countdown and compose cards embed the week id), so treat the new board
            // like a first load — full staggered entrance — rather than the
            // animate-immediately path meant for single late-fetched cards.
            let newWeekID = weekID(in: newItems)
            if lastSeenWeekID != nil, newWeekID != nil, newWeekID != lastSeenWeekID {
                initialIDs = Set(newItems.map(\.id))
                revealedIDs.removeAll()
            }
            lastSeenWeekID = newWeekID
        }
    }

    private func weekID(in items: [FeedItem]) -> UUID? {
        for item in items {
            if case .countdown(let week, _) = item { return week?.id }
        }
        return nil
    }

    // MARK: - Grid layouts

    private let rightColumnOffset: CGFloat = 64

    private var masonryGrid: some View {
        // Use cached columns; compute once on first render before onAppear fires.
        var left = leftColumn, right = rightColumn
        if left.isEmpty { (left, right) = distributeToColumns(masonryItems) }
        // During the reset take-down, render only the cards on screen. They're the
        // head of each column, so dropping the tails removes the off-screen cards
        // instantly without reflowing the rest. Computed inline (not from onChange
        // state) so the kept cards are present in the very pass isResetting flips —
        // then their opacity/offset animate instead of vanishing.
        if isResetting {
            let visible = visibleForReset()
            left = left.filter { visible.contains($0.id) }
            right = right.filter { visible.contains($0.id) }
        }
        return HStack(alignment: .top, spacing: 12) {
            LazyVStack(spacing: rowSpacing) {
                ForEach(Array(left.enumerated()), id: \.element.id) { idx, item in
                    masonryCell(item: item, animationIndex: idx * 2, isLeadingColumn: true)
                }
            }
            LazyVStack(spacing: rowSpacing) {
                ForEach(Array(right.enumerated()), id: \.element.id) { idx, item in
                    masonryCell(item: item, animationIndex: idx * 2 + 1, isLeadingColumn: false)
                }
            }
            .padding(.top, rightColumnOffset)
        }
        .padding(.horizontal, 16)
    }

    private var accessibleStack: some View {
        LazyVStack(spacing: rowSpacing) {
            ForEach(Array(masonryItems.enumerated()), id: \.element.id) { idx, item in
                masonryCell(item: item, animationIndex: idx, isLeadingColumn: false)
            }
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func masonryCell(item: FeedItem, animationIndex: Int, isLeadingColumn: Bool) -> some View {
        let rot = useRotation ? rotation(for: item) * rotationIntensity : 0
        // No .rotationEffect here. A post card's zoom-transition source lives inside
        // GridCard, and a source nested under an ancestor rotation resolves to a
        // rotated quad — which wrecks the interactive (swipe) back transition. GridCard
        // now applies `cardRotation` itself, beneath its own source. Non-post cards,
        // which have no transition source, are rotated in feedItemView instead.
        let revealed = revealedIDs.contains(item.id)
        let revealDelay = initialIDs.contains(item.id) ? Double(animationIndex) * 0.025 : 0
        feedItemView(for: item, cardRotation: rot, isLeadingColumn: isLeadingColumn)
            // Entrance animation — per item, so late-fetched cards animate too.
            // Anchored top-leading, not the `.center` default: center-anchoring
            // scales every pixel away from the card's midpoint, which visibly
            // translates the top-aligned, leading-aligned title text during the
            // grow-in — most noticeable on longer/multi-line titles, since
            // that's the densest block of legible content being displaced.
            // Anchoring where the content actually originates makes the card
            // grow outward from its own top-left corner instead.
            .opacity(revealed ? 1 : 0)
            .scaleEffect(revealed ? 1 : 0.94, anchor: .topLeading)
            .animation(
                reduceMotion ? .none : .smooth(duration: 0.4).delay(revealDelay),
                value: revealed
            )
            .onAppear {
                // First sight of this cell: it rendered hidden this frame, so
                // inserting the id now flips `revealed` with animation.
                revealedIDs.insert(item.id)
            }
            // Reset take-down: the on-screen cards fade + drift DOWN, staggered
            // bottom-to-top (delay from resetDelays). Off-screen cards were filtered
            // out of the columns, so they vanish instantly instead of animating.
            .offset(y: isResetting ? 180 : 0)
            .scaleEffect(isResetting ? 0.96 : 1, anchor: .top)
            .opacity(isResetting ? 0 : 1)
            .animation(
                reduceMotion ? .none :
                    .easeIn(duration: 0.45).delay(resetDelay(for: item)),
                value: isResetting
            )
            .onScrollVisibilityChange(threshold: 0.1) { visible in
                handleVisibilityChange(item: item, visible: visible)
            }
    }

    /// Which new-post cells are currently on screen (usually 0 or 1; briefly
    /// 2 mid-rollover while old and new coexist). See handleVisibilityChange.
    @State private var visibleNewPostIDs: Set<String> = []

    /// Maintains `visibleIDs` and forwards the header cards' visibility to the feed.
    ///
    /// The forwarded value is derived from the SET of visible new-post cells,
    /// not the latest event: at a board rollover the feed items get new ids,
    /// and the fresh card's "visible" fires BEFORE the old card's unmount
    /// fires "hidden" — forwarding events raw latched the feed on `false`
    /// with a compose card fully on screen, which is exactly how the bottom
    /// bar's + button appeared next to the dashed compose card every Monday.
    /// Same stale-completion family as the follow/unfollow inversion.
    private func handleVisibilityChange(item: FeedItem, visible: Bool) {
        if visible { visibleIDs.insert(item.id) } else { visibleIDs.remove(item.id) }
        switch item {
        case .newPost:
            if visible { visibleNewPostIDs.insert(item.id) } else { visibleNewPostIDs.remove(item.id) }
            onNewPostCardVisibilityChanged?(!visibleNewPostIDs.isEmpty)
        case .countdown, .post: break
        }
    }

    /// The set to animate on reset: the live on-screen set, or — if it's somehow
    /// empty (e.g. sitting at the top with no scroll callback yet fired) — a safe
    /// top-of-feed fallback so the take-down always has something to animate.
    private func visibleForReset() -> Set<String> {
        visibleIDs.isEmpty ? Set(masonryItems.prefix(10).map(\.id)) : visibleIDs
    }

    /// Bottom-to-top cascade delay for `item`, computed inline during the take-down.
    /// Feed order is ~top-to-bottom, so the lowest on-screen card (highest index)
    /// gets delay 0 and the wave travels upward. Off-screen items return 0 (they're
    /// filtered out of the columns anyway).
    private func resetDelay(for item: FeedItem) -> Double {
        guard isResetting else { return 0 }
        let ordered = masonryItems.filter { visibleForReset().contains($0.id) }
        guard let idx = ordered.firstIndex(where: { $0.id == item.id }) else { return 0 }
        return Double(ordered.count - 1 - idx) * 0.06
    }

    // MARK: - Item categorisation

    private var masonryItems: [FeedItem] { items }

    // MARK: - Column distribution

    private func distributeToColumns(_ items: [FeedItem]) -> ([FeedItem], [FeedItem]) {
        var leftH: CGFloat = 0, rightH: CGFloat = 0
        var left: [FeedItem] = [], right: [FeedItem] = []
        for item in items {
            let h = estimatedHeight(for: item)
            if leftH <= rightH {
                left.append(item); leftH += h + rowSpacing
            } else {
                right.append(item); rightH += h + rowSpacing
            }
        }
        return (left, right)
    }

    private func estimatedHeight(for item: FeedItem) -> CGFloat {
        // Base text card height (matches GridCard logic)
        let idealBase = columnWidth * 1.15
        let base: CGFloat = max(180, min(idealBase, 260))
        
        guard columnWidth > 0,
              case .post(let postID, _) = item,
              let post = store.feedPost(id: postID),
              let ratio = post.imageAspectRatio, ratio > 0 else { return base }
        let imageHeight = min(columnWidth / CGFloat(ratio), 300)
        return base + imageHeight - 16 // 16 = peekAmount
    }

    // MARK: - Item rendering

    @ViewBuilder
    private func feedItemView(for item: FeedItem, cardRotation: Double = 0, isLeadingColumn: Bool = false) -> some View {
        switch item {
        case .post(let postID, _):
            // The route is both the link value and the zoom source id, so the source
            // a destination looks up is always the exact card that pushed it.
            let route: BoardRoute = originatingProfileID.map {
                BoardRoute.postFromProfile(postID: postID, profileID: $0)
            } ?? .post(postID)
            NavigationLink(value: route) {
                FeedGridCard(postID: postID, cardNamespace: cardNamespace, transitionID: route, cardRotation: cardRotation, isLeadingColumn: isLeadingColumn, columnWidth: columnWidth)
            }
            .buttonStyle(.plain)
        case .countdown(let week, let isArchived):
            CountdownCard(week: week, isArchived: isArchived, columnWidth: columnWidth, celebrateBirthday: celebrateBirthday)
                .rotationEffect(.degrees(cardRotation))
        case .newPost(let isEnabled, _):
            if isEnabled, let onNewPost {
                Button(action: onNewPost) { NewPostCard(columnWidth: columnWidth, isEnabled: true) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("New post")
                    .rotationEffect(.degrees(cardRotation))
            } else {
                // Final hour: closed, non-tappable placeholder — same footprint.
                NewPostCard(columnWidth: columnWidth, isEnabled: false)
                    .accessibilityLabel("Posting closed — board clears soon")
                    .rotationEffect(.degrees(cardRotation))
            }
        }
    }

    // MARK: - Rotation

    private var useRotation: Bool {
        rotationIntensity > 0 && !typeSize.isAccessibilitySize && !reduceMotion
    }

    private func rotation(for item: FeedItem) -> Double {
        rotations[item.id, default: 0]
    }

    private func recomputeColumns() {
        (leftColumn, rightColumn) = distributeToColumns(masonryItems)
    }

    private func recomputeColumnsIfNeeded() {
        guard leftColumn.isEmpty else { return }
        recomputeColumns()
    }

    private func seedRotationsIfNeeded() {
        guard rotations.isEmpty else { return }
        seedRotationsForNewItems()
    }

    private func seedRotationsForNewItems() {
        for item in items where rotations[item.id] == nil {
            rotations[item.id] = Double.random(in: -3...3)
        }
    }
}
