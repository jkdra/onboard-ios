//
//  ProfileView.swift
//  On Board
//

import SwiftUI
import PhotosUI
import Supabase

enum ProfilePresentation {
    case sheet
    case navigation
}

struct ProfileView: View {
    let profile: Profile
    var presentation: ProfilePresentation = .sheet

    @Environment(BoardStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Namespace private var profileNamespace
    @State private var showAvatarViewer = false

    private let displayNameLimit = 50
    private let bioLimit = 300

    @State private var editMode = false
    @State private var draftDisplayName = ""
    @State private var draftHandle = ""
    @State private var handleAvailability: HandleAvailability = .idle
    @State private var handleCheckTask: Task<Void, Never>?
    @State private var draftBio = ""
    @State private var draftAvatarUrl: String?
    @State private var draftBirthday: Date?
    @State private var draftShowBirthday = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedPhotoData: Data?
    @State private var isUploadingPhoto = false
    @State private var uncroppedImage: UIImage?
    @State private var alertError: PresentableAlertError?

    // Moderation (other users' profiles only)
    @State private var reportTarget: ReportTarget?
    @State private var blockCandidate: BlockCandidate?
    @State private var isUpdatingBlock = false

    private var displayedProfile: Profile {
        store.profile(id: profile.id) ?? profile
    }

    private var canEdit: Bool { store.canEdit(profile: displayedProfile) }

    private let joinedFormatter: Date.FormatStyle = .dateTime
        .month(.wide)
        .day()
        .year()

    /// Month + day only — never the year. `showBirthday` opts into displaying the
    /// day people can wish them happy birthday, not their age.
    private var formattedBirthday: String? {
        guard let raw = displayedProfile.birthday else { return nil }
        guard let date = Self.birthdayFormatter.date(from: raw) else { return nil }
        return date.formatted(.dateTime.month(.wide).day())
    }

    private var minBirthdayAgeDate: Date {
        Calendar.current.date(byAdding: .year, value: -16, to: Date()) ?? Date()
    }

    // yyyy-MM-dd, matching the profiles.birthday column and the onboarding step's
    // encoding — POSIX locale so a device's regional calendar can't shift the parse.
    private static let birthdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    var body: some View {
        // Presentation modifiers split off from the layout chain (`profileScroll`)
        // so neither expression alone exceeds the Swift type-checker's budget.
        profileScroll
            .sheet(item: $reportTarget) { target in
                ReportContentSheet(target: target)
            }
            .alert("Block \(blockCandidate?.handle ?? "")?", isPresented: Binding(
                get: { blockCandidate != nil },
                set: { if !$0 { blockCandidate = nil } }
            ), presenting: blockCandidate) { candidate in
                Button("Block \(candidate.handle)", role: .destructive) {
                    Task { await blockUser(candidate) }
                }
            } message: { _ in
                Text("You won't see each other's posts or comments. You can unblock them anytime in Settings.")
            }
            .fullScreenCover(item: Binding<UIImage?>(
                get: { uncroppedImage },
                set: { uncroppedImage = $0 }
            )) { image in
                ImageCropView(image: image) { cropped in
                    uncroppedImage = nil
                    Task { await uploadCroppedPhoto(cropped) }
                } onCancel: {
                    uncroppedImage = nil
                    selectedPhotoItem = nil
                }
            }
            .fullScreenCover(isPresented: $showAvatarViewer) {
                if let urlString = displayedProfile.avatarUrl, let url = URL(string: urlString) {
                    ImageViewerView(url: url)
                        .navigationTransition(.zoom(sourceID: "avatarImage", in: profileNamespace))
                }
            }
            .task(id: profile.id) {
                // Ask directly whether a follows row exists for this one profile,
                // rather than depending on followedUserIDs from the board-wide
                // refresh cycle (which may not have run yet — e.g. right after a
                // cold launch — or may just be stale). A single targeted query is
                // the actual source of truth here.
                guard !canEdit, let boardService = store.boardService else { return }
                do {
                    if try await boardService.isFollowing(userID: profile.id) {
                        store.followedUserIDs.insert(profile.id)
                    } else {
                        store.followedUserIDs.remove(profile.id)
                    }
                } catch {
                    // Leave whatever's cached — a failed check shouldn't flip a
                    // correct "Following" state to "Follow".
                }
            }
            .task(id: profile.id) {
                await store.refreshPopScore(for: profile.id)
            }
            .presentableErrorAlert(error: $alertError)
    }

    private var profileScroll: some View {
        ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(alignment: .center, spacing: 16) {
                        avatar
                        identityHeader
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    bioSection

                    HStack(spacing: 6) {
                        Image(systemName: "calendar")
                        Text("joined \(displayedProfile.joinedAt.formatted(joinedFormatter).lowercased())")
                    }
                    .fontStyle(.footnote)
                    .foregroundStyle(.secondary)

                    birthdaySection

                    if !editMode {
                        if let popScore = store.popScore(for: profile.id) {
                            PopScoreView(score: popScore)
                                .padding(.top, 8)
                                .matchedGeometryEffect(id: "popScore", in: profileNamespace)
                        } else {
                            ProgressView()
                                .padding(.top, 8)
                                .matchedGeometryEffect(id: "popScore", in: profileNamespace)
                        }

                        if !canEdit {
                            followButton
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .safeAreaPadding()
                
                if !editMode {
                    userPostsSection
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .background {
                AnimatedStripesView(isActive: editMode)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if editMode {
                    Text("Tap any element to edit.")
                        .fontStyle(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
            }
            .navigationBackDisabled(editMode)
            .interactiveDismissDisabled(editMode)
            .keyboardDoneToolbar()
            .toolbar { profileToolbar }
    }

    // The identity/bio/birthday blocks and the follow button are pulled out of
    // `body` to keep that expression within the Swift type-checker's complexity
    // budget — inline, it tipped into an "unable to type-check in reasonable time"
    // failure once the birthday editor was added. Pure extraction, no behavior
    // change.
    @ToolbarContentBuilder
    private var profileToolbar: some ToolbarContent {
        if editMode {
            ToolbarItem(placement: .topBarLeading) {
                Button { cancelEditing() } label: {
                    Label("Cancel", systemImage: "xmark").fontWeight(.semibold)
                }
            }
            ToolbarItem(placement: .principal) {
                EditingIndicator()
                    .fontStyle(.title3)
                    .fixedSize()
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { saveProfile() } label: {
                    Label("Save", systemImage: "checkmark").fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSaveProfile)
            }
        } else {
            if presentation == .sheet {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Label("Close", systemImage: "xmark").fontWeight(.semibold) }
                }
            }
            if canEdit {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { beginEditing() } label: { Label("Edit", systemImage: "pencil").fontWeight(.semibold) }
                }
            } else {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            reportTarget = .profile(displayedProfile)
                        } label: {
                            Label("Report Profile", systemImage: "flag")
                        }
                        if store.isBlocked(userID: displayedProfile.id) {
                            Button {
                                Task { await unblockUser() }
                            } label: {
                                Label("Unblock \(displayedProfile.handle)", systemImage: "hand.raised.slash")
                            }
                        } else {
                            Button(role: .destructive) {
                                blockCandidate = BlockCandidate(
                                    userID: displayedProfile.id,
                                    handle: displayedProfile.handle
                                )
                            } label: {
                                Label("Block", systemImage: "hand.raised")
                            }
                            .tint(.red)
                        }
                    } label: {
                        Image(systemName: "ellipsis").fontWeight(.semibold)
                    }
                    .disabled(isUpdatingBlock)
                }
            }
        }
    }

    @ViewBuilder
    private var identityHeader: some View {
        VStack(alignment: .leading, spacing: 3) {
            if !editMode {
                // Display name is optional. When absent, promote the handle into the
                // title slot instead of leaving a blank title line above it. It keeps
                // the "username" id (not "displayName") so entering edit mode morphs
                // it smoothly into the now-secondary username field; the empty
                // display-name field simply fades in above it, which reads as "you can
                // add one" rather than a glitchy content swap.
                if displayedProfile.displayName.isEmpty {
                    Text(displayedProfile.handle)
                        .fontStyle(.title)
                        .fontWeight(.heavy)
                        .matchedGeometryEffect(id: "username", in: profileNamespace, anchor: .leading)
                } else {
                    Text(displayedProfile.displayName)
                        .fontStyle(.title)
                        .fontWeight(.heavy)
                        .matchedGeometryEffect(id: "displayName", in: profileNamespace, anchor: .leading)
                    Text(displayedProfile.handle)
                        .fontStyle(.subheadline)
                        .foregroundStyle(.secondary)
                        .matchedGeometryEffect(id: "username", in: profileNamespace, anchor: .leading)
                }
            } else {
                TextField("Display Name", text: $draftDisplayName)
                    .lineLimit(1)
                    .fontStyle(.title)
                    .fontWeight(.heavy)
                    .keyboardType(.namePhonePad)
                    .textContentType(.name)
                    .textInputAutocapitalization(.words)
                    .matchedGeometryEffect(id: "displayName", in: profileNamespace, anchor: .leading)
                if draftDisplayName.count >= Int(Double(displayNameLimit) * 0.8) {
                    Text("\(draftDisplayName.count)/\(displayNameLimit)")
                        .fontStyle(.caption2)
                        .foregroundStyle(draftDisplayName.count > displayNameLimit ? Color.red : Color.orange)
                        .monospacedDigit()
                }
                TextField("username", text: $draftHandle)
                    .lineLimit(1)
                    .fontStyle(.subheadline)
                    .foregroundStyle(.secondary)
                    .keyboardType(.asciiCapable)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .matchedGeometryEffect(id: "username", in: profileNamespace, anchor: .leading)
                    .onChange(of: draftHandle) { _, _ in
                        scheduleHandleAvailabilityCheck()
                    }
                handleAvailabilityLabel
            }
        }
    }

    @ViewBuilder
    private var bioSection: some View {
        if !editMode {
            if let bio = displayedProfile.bio, !bio.isEmpty {
                Text(bio)
                    .fontStyle(.body)
                    .foregroundStyle(.primary)
                    .matchedGeometryEffect(id: "bio", in: profileNamespace, anchor: .leading)
            }
        } else {
            TextField("Bio", text: $draftBio, axis: .vertical)
                .fontStyle(.body)
                .foregroundStyle(.primary)
                .keyboardType(.twitter)
                .matchedGeometryEffect(id: "bio", in: profileNamespace, anchor: .leading)
            if draftBio.count >= Int(Double(bioLimit) * 0.8) {
                Text("\(draftBio.count)/\(bioLimit)")
                    .fontStyle(.caption2)
                    .foregroundStyle(draftBio.count > bioLimit ? Color.red : Color.orange)
                    .monospacedDigit()
            }
        }
    }

    @ViewBuilder
    private var birthdaySection: some View {
        if !editMode {
            if displayedProfile.showBirthday, let birthday = formattedBirthday {
                HStack(spacing: 6) {
                    Image(systemName: "birthday.cake")
                    Text(birthday)
                }
                .fontStyle(.footnote)
                .foregroundStyle(.secondary)
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                BirthdayGraphicalPicker(date: $draftBirthday, maximumDate: minBirthdayAgeDate)
                Toggle("Show month and day on my profile", isOn: $draftShowBirthday)
                    .fontStyle(.body)
                    .tint(.primary)
            }
        }
    }

    @ViewBuilder
    private var followButton: some View {
        let isFollowing = store.followedUserIDs.contains(profile.id)
        Button {
            Task {
                if isFollowing {
                    await store.unfollowUser(id: profile.id)
                } else {
                    await store.followUser(id: profile.id)
                }
            }
        } label: {
            Label(
                isFollowing ? "Following" : "Follow",
                systemImage: isFollowing ? "person.fill.checkmark" : "person.badge.plus"
            )
        }
        .buttonStyle(isFollowing ? .boardSecondary : .boardPrimary)
        .padding(.top, 8)
        .matchedGeometryEffect(id: "watchButton", in: profileNamespace)
    }

    private var avatar: some View {
        ZStack(alignment: .bottomTrailing) {
            if editMode {
                let photoData = selectedPhotoData
                let uploading = isUploadingPhoto
                let draftUrl = draftAvatarUrl
                let currentProfile = displayedProfile
                
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    ZStack(alignment: .bottomTrailing) {
                        ZStack {
                            if let data = photoData, let uiImage = UIImage(data: data) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 92, height: 92)
                                    .clipShape(Circle())
                                    .overlay(Circle().stroke(Color.secondary.opacity(0.3), lineWidth: 1))
                                    .opacity(uploading ? 0.5 : 1.0)
                            } else {
                                AvatarView(profile: draftUrl.map { url in
                                    Profile(id: currentProfile.id, handle: currentProfile.handle, displayName: currentProfile.displayName, bio: currentProfile.bio, avatarUrl: url)
                                } ?? currentProfile, size: .large)
                                .opacity(uploading ? 0.5 : 1.0)
                            }
                            
                            if uploading {
                                ProgressView()
                                    .controlSize(.regular)
                                    .tint(.primary)
                            }
                        }
                        
                        Image(systemName: "camera.fill")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color(uiColor: .systemBackground))
                            .frame(width: 28, height: 28)
                            .background(Color.primary)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color(uiColor: .systemBackground), lineWidth: 2))
                            .offset(x: 4, y: 4)
                    }
                }
                .buttonStyle(.plain)
                .disabled(isUploadingPhoto)
            } else {
                Button {
                    if displayedProfile.avatarUrl != nil {
                        showAvatarViewer = true
                    }
                } label: {
                    AvatarView(profile: displayedProfile, size: .large)
                }
                .buttonStyle(.plain)
                .matchedTransitionSource(id: "avatarImage", in: profileNamespace)
            }
        }
        .accessibilityLabel("\(displayedProfile.displayName) avatar")
        .onChange(of: selectedPhotoItem) { _, newItem in
            Task { await loadAndUploadPhoto(newItem) }
        }
    }

    private enum HandleAvailability: Equatable {
        case idle
        case checking
        case available
        case unavailable
        case invalid
        case offline
    }

    @ViewBuilder
    private var handleAvailabilityLabel: some View {
        switch handleAvailability {
        case .idle, .available:
            EmptyView()
        case .checking:
            Label("Checking availability…", systemImage: "ellipsis")
                .fontStyle(.caption2)
                .foregroundStyle(.secondary)
        case .unavailable:
            Label("Already taken", systemImage: "xmark.circle.fill")
                .fontStyle(.caption2)
                .foregroundStyle(.red)
        case .invalid:
            Label("2–32 characters: letters, numbers, . or _", systemImage: "exclamationmark.circle.fill")
                .fontStyle(.caption2)
                .foregroundStyle(.orange)
        case .offline:
            Label("Offline — connect to check availability", systemImage: "wifi.slash")
                .fontStyle(.caption2)
                .foregroundStyle(.orange)
        }
    }

    private func beginEditing() {
        draftDisplayName = displayedProfile.displayName
        draftHandle = displayedProfile.handle
        // Your own current handle is always valid/available — no need to
        // round-trip a check before the user has actually changed anything.
        handleAvailability = .available
        draftBio = displayedProfile.bio ?? ""
        draftAvatarUrl = displayedProfile.avatarUrl
        draftBirthday = displayedProfile.birthday.flatMap { Self.birthdayFormatter.date(from: $0) }
        draftShowBirthday = displayedProfile.showBirthday
        selectedPhotoData = nil
        selectedPhotoItem = nil
        withAnimation(.smooth(duration: 0.3)) { editMode = true }
    }

    private var canSaveProfile: Bool {
        draftDisplayName.count <= displayNameLimit
            && draftBio.count <= bioLimit
            && HandleRules.isValid(draftHandle.trimmed)
            && handleAvailability == .available
            && draftBirthday != nil
    }

    private func saveProfile() {
        Task {
            await store.updateProfile(
                displayName: draftDisplayName.trimmed,
                handle: draftHandle.trimmed,
                bio: draftBio.trimmed.isEmpty ? nil : draftBio.trimmed,
                avatarUrl: draftAvatarUrl,
                birthday: draftBirthday.map { Self.birthdayFormatter.string(from: $0) },
                showBirthday: draftShowBirthday
            )
            withAnimation(.smooth(duration: 0.3)) { editMode = false }
        }
    }

    private func scheduleHandleAvailabilityCheck() {
        handleCheckTask?.cancel()
        let candidate = draftHandle.trimmed

        if candidate == displayedProfile.handle {
            handleAvailability = .available
            return
        }

        guard !candidate.isEmpty else {
            handleAvailability = .invalid
            return
        }

        guard HandleRules.isValid(candidate) else {
            handleAvailability = .invalid
            return
        }

        handleAvailability = .checking
        handleCheckTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }

            let result = await store.checkHandleAvailable(candidate)
            guard !Task.isCancelled, draftHandle.trimmed == candidate else { return }
            switch result {
            case .available: handleAvailability = .available
            case .taken: handleAvailability = .unavailable
            case .networkError: handleAvailability = .offline
            }
        }
    }

    private func cancelEditing() {
        handleCheckTask?.cancel()
        selectedPhotoData = nil
        selectedPhotoItem = nil
        draftAvatarUrl = nil
        withAnimation(.smooth(duration: 0.3)) { editMode = false }
    }

    // MARK: - Posts Section

    private var userPostsSection: some View {
        let userPosts = store.feedItems.filter { item in
            if case .post(let id, _) = item, let post = store.feedPost(id: id) {
                return post.authorId == profile.id
            }
            return false
        }
        
        return Group {
            if !userPosts.isEmpty {
                VStack(alignment: .leading, spacing: 16) {
                    Divider()
                        .padding(.horizontal)
                        .padding(.top, 8)
                    
                    Text("This Week's Posts")
                        .fontStyle(.headline)
                        .padding(.horizontal)
                    
                    // No cardNamespace override: it comes from the environment so the
                    // cards register in ContentView's namespace, which is the one
                    // routeDestination's .zoom reads. profileNamespace stays scoped to
                    // this screen's matchedGeometryEffect / avatar zoom.
                    BoardFeedView(
                        items: userPosts,
                        originatingProfileID: profile.id
                    )
                }
                .padding(.top, 8)
            }
        }
    }

    // MARK: - Moderation

    private func blockUser(_ candidate: BlockCandidate) async {
        isUpdatingBlock = true
        defer { isUpdatingBlock = false }
        do {
            try await store.block(userID: candidate.userID)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            if presentation == .sheet {
                dismiss()
            }
        } catch {
            alertError = store.presentableModerationError(error)
        }
    }

    private func unblockUser() async {
        isUpdatingBlock = true
        defer { isUpdatingBlock = false }
        do {
            try await store.unblock(userID: displayedProfile.id)
        } catch {
            alertError = store.presentableModerationError(error)
        }
    }

    private func loadAndUploadPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        guard let uiImage = UIImage(data: data) else { return }
        
        await MainActor.run {
            uncroppedImage = uiImage
        }
    }

    private func uploadCroppedPhoto(_ image: UIImage) async {
        // Optimistically set the selected data to preview
        selectedPhotoData = image.jpegData(compressionQuality: 0.85)
        
        isUploadingPhoto = true
        defer { isUploadingPhoto = false }

        guard let userID = store.currentUserID else { return }

        if let result = await ImageUploader.upload(input: .uiImage(image), type: .profilePicture, userID: userID) {
            draftAvatarUrl = result.url
        } else {
            // Revert the optimistic preview so the avatar shown matches what Save
            // would actually keep, and tell the user instead of failing silently.
            selectedPhotoData = nil
            selectedPhotoItem = nil
            alertError = PresentableAlertError(
                message: "Your photo couldn't be uploaded.",
                recoverySuggestion: "Check your connection and try again."
            )
        }
    }
}

extension UIImage: @retroactive Identifiable {
    public var id: Int { hash }
}


#Preview {
    NavigationStack {
        ProfileView(profile: .currentUser)
    }
    .environment(BoardStore.sampleBoard(currentUserID: SampleProfileID.maya))
}

struct PopScoreView: View {
    let score: [Reaction: Int]
    
    var body: some View {
        let total = max(1, score.values.reduce(0, +))
        let sortedReactions = Reaction.defaultOrder.filter { (score[$0] ?? 0) > 0 }
        
        VStack(alignment: .leading, spacing: 12) {
            Text("Pop Score")
                .fontStyle(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            
            if score.isEmpty {
                Text("Post more to start building your score!")
                    .fontStyle(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        ForEach(sortedReactions, id: \.self) { reaction in
                            let count = score[reaction] ?? 0
                            // subtract 2 for the spacing to keep total width correct
                            let spacingCorrection = CGFloat(sortedReactions.count - 1) * 2.0 / CGFloat(sortedReactions.count)
                            let width = max(0, geo.size.width * CGFloat(count) / CGFloat(total) - spacingCorrection)
                            Rectangle()
                                .fill(color(for: reaction))
                                .frame(width: width)
                        }
                    }
                }
                .frame(height: 12)
                .clipShape(Capsule())
                
                HStack(spacing: 16) {
                    ForEach(sortedReactions, id: \.self) { reaction in
                        let count = score[reaction] ?? 0
                        HStack(spacing: 4) {
                            Text(reaction.emoji)
                            Text("\(Int(round(Double(count) / Double(total) * 100)))%")
                                .fontStyle(.caption2)
                                .fontWeight(.medium)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
    
    private func color(for reaction: Reaction) -> Color {
        switch reaction {
        case .laugh: return .yellow
        case .hug: return .green
        case .like: return .pink
        case .dislike: return .gray
        }
    }
}
