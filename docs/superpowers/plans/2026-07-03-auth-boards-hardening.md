# Auth & Board-Loading Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make sign-in-method unlinking actually safe, fix the never-working storage uploads, make waitlist approval reach the app without a relaunch, and remove the dev-board fallbacks that show the wrong board.

**Architecture:** SwiftUI + Supabase iOS app. All stores are `@Observable @MainActor`; every backend call goes through a protocol (`AuthService`, `BoardService`, `OnboardingService`) with live (`Supabase*`) and mock impls that must stay in sync. Changes here touch the auth session model (identity-derived truth), two views, one store, plus two Supabase migrations applied via the Supabase MCP.

**Tech Stack:** Swift 6.3, iOS 18 minimum, Swift Testing (`@Test` / `#expect`, NOT XCTest), supabase-swift SDK, Postgres/Supabase backend.

## Global Constraints

- Build check: `xcodebuild -scheme "On Board" -destination "generic/platform=iOS Simulator" build 2>&1 | grep -E "error:|^\*\* BUILD (SUCCEEDED|FAILED)"` — must end `** BUILD SUCCEEDED **`.
- Tests: `xcodebuild test -scheme "On Board" -destination "platform=iOS Simulator,name=iPhone 16 Pro,OS=18.5" -parallel-testing-enabled NO` (if the destination errors with duplicate simulators, list with `xcrun simctl list devices available` and pass `-destination "id=<UDID>"`).
- Test file: all tests live in `On BoardTests/On_BoardTests.swift` (single file, multiple `struct` suites). Use Swift Testing.
- The Read tool needs literal spaces in paths (`On Board/...`), never `On\ Board`.
- The `supabase/` folder is intentionally NOT in git — never `git add` anything under it.
- Migrations: write the SQL file into `supabase/migrations/` locally AND apply it to the remote with the Supabase MCP `apply_migration` tool (project is already connected). Do not hand-edit the remote ledger.
- Both `AuthService` impls (`SupabaseAuthService`, `MockAuthService`) must stay in sync for any protocol change.
- Commit after each task; end commit messages with `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.

---

### Task 1: Identity-derived sign-in-method counting

The bug: `AuthSession.email` is populated by Supabase from an OAuth provider even when no email sign-in method exists, so `remainingSignInMethodCount` overcounts and lets a user unlink their only real identity. Truth = the `userIdentities()` list.

**Files:**
- Modify: `On Board/Auth/AuthSession.swift`
- Modify: `On Board/Auth/SignInMethodKind.swift`
- Modify: `On Board/Auth/SupabaseAuthService.swift` (mapSession, ~line 293)
- Modify: `On Board/Auth/MockAuthService.swift` (makeSession + call sites)
- Test: `On BoardTests/On_BoardTests.swift`

**Interfaces:**
- Produces: `AuthSession.hasEmailIdentity: Bool`, `AuthSession.hasPhoneIdentity: Bool` (new stored properties, default `false`); `signInMethodKinds` / `remainingSignInMethodCount(excludingIdentityId:)` / `hasLinked(_:)` now derive from those flags + `linkedIdentities` only. Task 8's UI relies on `canUnlinkIdentity(_:)` being correct.

- [ ] **Step 1: Write the failing tests** — append to `On BoardTests/On_BoardTests.swift`:

```swift
@MainActor
struct SignInMethodCountingTests {
    private func session(
        email: String? = nil,
        phone: String? = nil,
        hasEmailIdentity: Bool = false,
        hasPhoneIdentity: Bool = false,
        identities: [LinkedIdentity] = []
    ) -> AuthSession {
        AuthSession(
            userId: UUID(),
            primaryProvider: .google,
            email: email,
            phone: phone,
            hasEmailIdentity: hasEmailIdentity,
            hasPhoneIdentity: hasPhoneIdentity,
            linkedIdentities: identities
        )
    }

    // A Google-only user has user.email copied from the OAuth provider.
    // That copied email must NOT count as a sign-in method.
    @Test func oauthCopiedEmailDoesNotAllowUnlinkingSoleIdentity() {
        let google = LinkedIdentity(id: "g1", provider: .google, email: "me@gmail.com")
        let s = session(email: "me@gmail.com", identities: [google])
        #expect(!s.canUnlinkIdentity(google))
        #expect(s.remainingSignInMethodCount(excludingIdentityId: "g1") == 0)
    }

    @Test func realEmailIdentityAllowsUnlinkingOAuth() {
        let google = LinkedIdentity(id: "g1", provider: .google, email: "me@gmail.com")
        let s = session(email: "me@gmail.com", hasEmailIdentity: true, identities: [google])
        #expect(s.canUnlinkIdentity(google))
    }

    @Test func hasLinkedUsesIdentityFlagsNotCopiedFields() {
        let s = session(email: "me@gmail.com", phone: "+15555550100")
        #expect(!s.hasLinked(.email))
        #expect(!s.hasLinked(.phone))
        let s2 = session(hasEmailIdentity: true, hasPhoneIdentity: true)
        #expect(s2.hasLinked(.email))
        #expect(s2.hasLinked(.phone))
    }

    @Test func decodingOldSessionWithoutFlagsDefaultsToFalse() throws {
        let json = """
        {"userId":"\(UUID().uuidString)","primaryProvider":"google","email":"a@b.co","linkedIdentities":[]}
        """
        let decoded = try JSONDecoder().decode(AuthSession.self, from: Data(json.utf8))
        #expect(!decoded.hasEmailIdentity)
        #expect(!decoded.hasPhoneIdentity)
    }
}
```

- [ ] **Step 2: Run to verify failure** — build-only is enough to see the compile error (no such init parameter):

Run: `xcodebuild -scheme "On Board" -destination "generic/platform=iOS Simulator" build 2>&1 | grep -E "error:|^\*\* BUILD (SUCCEEDED|FAILED)"`
Expected: FAILED — `extra arguments at positions ... in call` / `hasEmailIdentity` unknown.

- [ ] **Step 3: Extend `AuthSession`** — add the two flags (stored, default false, Codable-tolerant). Full replacement for the struct body pieces that change:

```swift
struct AuthSession: Equatable, Codable, Sendable {
    let userId: UUID
    let primaryProvider: AuthProvider
    let email: String?
    let phone: String?
    /// True only when a real `email` / `phone` provider identity exists in
    /// `auth.identities` — `email`/`phone` above may be copied from an OAuth
    /// provider and are display-only.
    let hasEmailIdentity: Bool
    let hasPhoneIdentity: Bool
    let linkedIdentities: [LinkedIdentity]

    /// Backward-compatible alias for the primary sign-in provider.
    var provider: AuthProvider { primaryProvider }

    init(
        userId: UUID,
        primaryProvider: AuthProvider,
        email: String? = nil,
        phone: String? = nil,
        hasEmailIdentity: Bool = false,
        hasPhoneIdentity: Bool = false,
        linkedIdentities: [LinkedIdentity] = []
    ) {
        self.userId = userId
        self.primaryProvider = primaryProvider
        self.email = email
        self.phone = phone
        self.hasEmailIdentity = hasEmailIdentity
        self.hasPhoneIdentity = hasPhoneIdentity
        self.linkedIdentities = linkedIdentities
    }

    init(
        userId: UUID,
        provider: AuthProvider,
        email: String? = nil,
        phone: String? = nil,
        hasEmailIdentity: Bool = false,
        hasPhoneIdentity: Bool = false,
        linkedIdentities: [LinkedIdentity] = []
    ) {
        self.init(
            userId: userId,
            primaryProvider: provider,
            email: email,
            phone: phone,
            hasEmailIdentity: hasEmailIdentity,
            hasPhoneIdentity: hasPhoneIdentity,
            linkedIdentities: linkedIdentities
        )
    }

    enum CodingKeys: String, CodingKey {
        case userId
        case primaryProvider
        case provider
        case email
        case phone
        case hasEmailIdentity
        case hasPhoneIdentity
        case linkedIdentities
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userId = try container.decode(UUID.self, forKey: .userId)
        primaryProvider = try container.decodeIfPresent(AuthProvider.self, forKey: .primaryProvider)
            ?? container.decode(AuthProvider.self, forKey: .provider)
        email = try container.decodeIfPresent(String.self, forKey: .email)
        phone = try container.decodeIfPresent(String.self, forKey: .phone)
        hasEmailIdentity = try container.decodeIfPresent(Bool.self, forKey: .hasEmailIdentity) ?? false
        hasPhoneIdentity = try container.decodeIfPresent(Bool.self, forKey: .hasPhoneIdentity) ?? false
        linkedIdentities = try container.decodeIfPresent([LinkedIdentity].self, forKey: .linkedIdentities) ?? []
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(userId, forKey: .userId)
        try container.encode(primaryProvider, forKey: .primaryProvider)
        try container.encodeIfPresent(email, forKey: .email)
        try container.encodeIfPresent(phone, forKey: .phone)
        try container.encode(hasEmailIdentity, forKey: .hasEmailIdentity)
        try container.encode(hasPhoneIdentity, forKey: .hasPhoneIdentity)
        try container.encode(linkedIdentities, forKey: .linkedIdentities)
    }
}
```

- [ ] **Step 4: Rewrite the counting logic in `SignInMethodKind.swift`** — replace the `AuthSession` extension bodies:

```swift
extension AuthSession {
    var signInMethodKinds: [SignInMethodKind] {
        var methods: [SignInMethodKind] = []
        if hasPhoneIdentity { methods.append(.phone) }
        if hasEmailIdentity { methods.append(.email) }
        for identity in linkedIdentities {
            switch identity.provider {
            case .apple where !methods.contains(.apple):
                methods.append(.apple)
            case .google where !methods.contains(.google):
                methods.append(.google)
            default:
                break
            }
        }
        return methods
    }

    func remainingSignInMethodCount(excludingIdentityId: String? = nil) -> Int {
        var count = 0
        if hasPhoneIdentity { count += 1 }
        if hasEmailIdentity { count += 1 }
        for identity in linkedIdentities where identity.id != excludingIdentityId {
            count += 1
        }
        return count
    }

    func canUnlinkIdentity(_ identity: LinkedIdentity) -> Bool {
        remainingSignInMethodCount(excludingIdentityId: identity.id) > 0
    }

    func hasLinked(_ provider: AuthProvider) -> Bool {
        switch provider {
        case .phone:
            hasPhoneIdentity
        case .email:
            hasEmailIdentity
        case .apple, .google:
            linkedIdentities.contains { $0.provider == provider }
        }
    }
}
```

- [ ] **Step 5: Feed the flags from Supabase** — in `SupabaseAuthService.swift`, replace `mapSession(_:identities:)`:

```swift
    private static func mapSession(_ session: Session, identities: [UserIdentity]) -> AuthSession {
        let user = session.user
        let linkedIdentities = identities.compactMap { identity -> LinkedIdentity? in
            let email = identity.identityData?["email"]?.stringValue
            return LinkedIdentity.fromSupabaseProvider(identity.provider, id: identity.id, email: email)
        }
        let identityProviders = Set(identities.map(\.provider))

        return AuthSession(
            userId: user.id,
            primaryProvider: primaryProvider(from: user, identities: identities),
            email: user.email,
            phone: user.phone,
            hasEmailIdentity: identityProviders.contains("email"),
            hasPhoneIdentity: identityProviders.contains("phone"),
            linkedIdentities: linkedIdentities
        )
    }
```

- [ ] **Step 6: Keep the mock in sync** — in `MockAuthService.swift`, `makeSession` treats a non-nil email/phone as a real linked identity (mock semantics: you only get one by linking it):

```swift
    private func makeSession(
        userId: UUID,
        primaryProvider: AuthProvider,
        email: String?,
        phone: String?,
        linkedProviders: [AuthProvider]
    ) -> AuthSession {
        let linkedIdentities = linkedProviders
            .filter { $0 == .apple || $0 == .google }
            .map { provider in
                LinkedIdentity(
                    id: "mock-\(provider.rawValue)",
                    provider: provider,
                    email: email
                )
            }

        return AuthSession(
            userId: userId,
            primaryProvider: primaryProvider,
            email: email,
            phone: phone,
            hasEmailIdentity: email?.isEmpty == false,
            hasPhoneIdentity: phone?.isEmpty == false,
            linkedIdentities: linkedIdentities
        )
    }
```

One nuance: in `signIn(with:)` the mock passes `email: provider == .email ? "you@example.com" : nil` — with the new semantics a mock Google sign-in has `email: nil`, so `hasEmailIdentity` is correctly false. No further mock changes needed.

- [ ] **Step 7: Run the new suite**

Run: `xcodebuild test -scheme "On Board" -destination "platform=iOS Simulator,name=iPhone 16 Pro,OS=18.5" -parallel-testing-enabled NO -only-testing "On BoardTests/SignInMethodCountingTests" 2>&1 | tail -20`
Expected: all 4 tests PASS.

- [ ] **Step 8: Commit**

```bash
git add "On Board/Auth/AuthSession.swift" "On Board/Auth/SignInMethodKind.swift" "On Board/Auth/SupabaseAuthService.swift" "On Board/Auth/MockAuthService.swift" "On BoardTests/On_BoardTests.swift"
git commit -m "Count sign-in methods from real auth identities, not OAuth-copied email/phone"
```

---

### Task 2: Fix storage uploads (upsert + policy)

Diagnosis (verified live): no object has ever landed in `storage.objects`; the RLS INSERT policy passes when simulated; the avatar upload's `upsert: true` requires an UPDATE policy that doesn't exist → 400.

**Files:**
- Modify: `On Board/Views/Onboarding/OnboardingProfileStepView.swift:206-213`
- Create: `supabase/migrations/<timestamp>_storage_objects_update_policies.sql` (NOT git-tracked)

**Interfaces:** none consumed downstream.

- [ ] **Step 1: Client fix** — in `loadAndUploadPhoto`, change the upload options and correct the stale comment:

```swift
        // Storage RLS checks the path's folder segment against `auth.uid()::text`
        // (lowercase), and Supabase requires an UPDATE policy for upsert uploads —
        // the filename is a fresh UUID every time, so plain insert is correct.
        let path = "\(userID.uuidString.lowercased())/\(UUID().uuidString).jpg"
        do {
            try await client.storage
                .from("avatars")
                .upload(path, data: jpeg, options: FileOptions(contentType: "image/jpeg", upsert: false))
```

- [ ] **Step 2: Hardening migration** — write the file locally with a current timestamp name, e.g. `supabase/migrations/20260703{HHMMSS}_storage_objects_update_policies.sql`:

```sql
-- Owner-scoped UPDATE policies so future upsert/overwrite uploads work.
create policy "avatars_update" on storage.objects
  for update
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = (auth.uid())::text)
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = (auth.uid())::text);

create policy "post_images_update" on storage.objects
  for update
  using (bucket_id = 'post-images' and (storage.foldername(name))[1] = (auth.uid())::text)
  with check (bucket_id = 'post-images' and (storage.foldername(name))[1] = (auth.uid())::text);
```

Apply the same SQL to the remote with the Supabase MCP tool `apply_migration` (name: `storage_objects_update_policies`).

- [ ] **Step 3: Build check**

Run: `xcodebuild -scheme "On Board" -destination "generic/platform=iOS Simulator" build 2>&1 | grep -E "error:|^\*\* BUILD (SUCCEEDED|FAILED)"`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit** (client file only — supabase/ stays untracked)

```bash
git add "On Board/Views/Onboarding/OnboardingProfileStepView.swift"
git commit -m "Fix avatar upload: drop upsert (blocked by missing storage UPDATE policy)"
```

---

### Task 3: Stop Apple sign-in from clobbering display names

Apple re-sends `fullName` after the user revokes & re-authorizes; the current code overwrites `profiles.display_name` unconditionally.

**Files:**
- Modify: `On Board/Auth/SupabaseAuthService.swift:84-109` (`signInWithApple`)
- Test: `On BoardTests/On_BoardTests.swift`

**Interfaces:**
- Produces: `AppleNameAdoption.shouldAdopt(currentDisplayName:) -> Bool` (static, nonisolated, defined in `SupabaseAuthService.swift`).

- [ ] **Step 1: Failing test**

```swift
struct AppleNameAdoptionTests {
    @Test func adoptsWhenCurrentNameEmpty() {
        #expect(AppleNameAdoption.shouldAdopt(currentDisplayName: ""))
        #expect(AppleNameAdoption.shouldAdopt(currentDisplayName: "   "))
        #expect(AppleNameAdoption.shouldAdopt(currentDisplayName: nil))
    }

    @Test func neverOverwritesAChosenName() {
        #expect(!AppleNameAdoption.shouldAdopt(currentDisplayName: "Jawad Khadra"))
    }
}
```

- [ ] **Step 2: Run to verify failure** — build fails: `AppleNameAdoption` undefined.

- [ ] **Step 3: Implement** — add to `SupabaseAuthService.swift` (file scope) and rework the fullName block:

```swift
enum AppleNameAdoption {
    /// Apple re-sends the full name when a user revokes and re-authorizes the app.
    /// Only adopt it while the profile has no chosen display name — never overwrite.
    nonisolated static func shouldAdopt(currentDisplayName: String?) -> Bool {
        (currentDisplayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
```

In `signInWithApple`, replace the `if let fullName { ... }` block:

```swift
        if let fullName {
            _ = try? await client.auth.update(
                user: UserAttributes(data: ["full_name": .string(fullName)])
            )
            if let userID = client.auth.currentSession?.user.id {
                struct NameRow: Decodable {
                    let displayName: String?
                    enum CodingKeys: String, CodingKey { case displayName = "display_name" }
                }
                let row: NameRow? = try? await client
                    .from("profiles")
                    .select("display_name")
                    .eq("id", value: userID.uuidString)
                    .single()
                    .execute()
                    .value
                if AppleNameAdoption.shouldAdopt(currentDisplayName: row?.displayName) {
                    _ = try? await client
                        .from("profiles")
                        .update(["display_name": fullName])
                        .eq("id", value: userID.uuidString)
                        .execute()
                }
            }
        }
```

- [ ] **Step 4: Run tests**

Run: `xcodebuild test -scheme "On Board" -destination "platform=iOS Simulator,name=iPhone 16 Pro,OS=18.5" -parallel-testing-enabled NO -only-testing "On BoardTests/AppleNameAdoptionTests" 2>&1 | tail -10`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add "On Board/Auth/SupabaseAuthService.swift" "On BoardTests/On_BoardTests.swift"
git commit -m "Only adopt Apple full name when the profile has no display name yet"
```

---

### Task 4: Offline restore & resilient sign-out

`restoreSession` currently swallows connectivity failures and returns nil → a signed-in user launching offline (expired access token, path monitor claiming connected) lands on SignInView. Route that case to `OfflineGateView` and auto-retry. Sign-out must never strand the user in `.failed`.

**Files:**
- Modify: `On Board/Auth/AuthState.swift` (new case)
- Modify: `On Board/Auth/AuthStore.swift` (`restoreSession`, `signOut`, `cancelSignIn`)
- Modify: `On Board/Auth/SupabaseAuthService.swift` (`restoreSession`, `signOut`)
- Modify: `On Board/Views/Shared/RootView.swift` (gate + retry)
- Test: `On BoardTests/On_BoardTests.swift`

**Interfaces:**
- Produces: `AuthState.restoreFailedOffline` (no associated value; `isSignedIn == false`).

- [ ] **Step 1: Failing test**

```swift
/// AuthService stub whose restore/sign-out behavior is scripted per test.
/// Every other requirement is unreachable in these tests.
private final class ScriptedAuthService: AuthService, @unchecked Sendable {
    var restoreResult: Result<AuthSession?, Error> = .success(nil)
    var signOutError: Error?

    func restoreSession() async throws -> AuthSession? { try restoreResult.get() }
    func signOut() async throws { if let signOutError { throw signOutError } }

    func signIn(with provider: AuthProvider) async throws -> AuthSession { fatalError("unused") }
    func signInWithApple(idToken: String, nonce: String?, fullName: String?) async throws -> AuthSession { fatalError("unused") }
    func signInWithGoogle() async throws -> AuthSession { fatalError("unused") }
    func sendPhoneOTP(phone: String) async throws { fatalError("unused") }
    func verifyPhoneOTP(phone: String, token: String) async throws -> AuthSession { fatalError("unused") }
    func sendEmailOTP(email: String) async throws { fatalError("unused") }
    func verifyEmailOTP(email: String, token: String) async throws -> AuthSession { fatalError("unused") }
    func linkApple(idToken: String, nonce: String?) async throws -> AuthSession { fatalError("unused") }
    func linkGoogle() async throws -> AuthSession { fatalError("unused") }
    func sendLinkPhoneOTP(phone: String) async throws { fatalError("unused") }
    func verifyLinkPhoneOTP(phone: String, token: String) async throws -> AuthSession { fatalError("unused") }
    func sendLinkEmailOTP(email: String) async throws { fatalError("unused") }
    func verifyLinkEmailOTP(email: String, token: String) async throws -> AuthSession { fatalError("unused") }
    func unlinkIdentity(id: String) async throws -> AuthSession { fatalError("unused") }
    func refreshAuthSession() async throws -> AuthSession? { nil }
    func deleteAccount() async throws { fatalError("unused") }
}
// NOTE: mirror the real `AuthService` protocol exactly — check
// `On Board/Auth/AuthService.swift` and adjust signatures if they differ.

@MainActor
struct AuthRestoreOfflineTests {
    @Test func connectivityFailureDuringRestoreBecomesRestoreFailedOffline() async {
        let service = ScriptedAuthService()
        service.restoreResult = .failure(AuthError.networkUnavailable)
        let store = AuthStore(service: service)
        await store.restoreSession()
        #expect(store.state == .restoreFailedOffline)
        #expect(!store.isSignedIn)
    }

    @Test func signOutErrorStillSignsOutLocally() async {
        let service = ScriptedAuthService()
        service.signOutError = AuthError.networkUnavailable
        let store = AuthStore(service: service)
        await store.signOut()
        #expect(store.state == .signedOut)
    }
}
```

- [ ] **Step 2: Run to verify failure** — compile error: `restoreFailedOffline` undefined.

- [ ] **Step 3: Implement**

`AuthState.swift` — add the case:

```swift
enum AuthState: Equatable, Sendable {
    case signedOut
    case signingIn(AuthProvider)
    case signedIn(AuthSession)
    /// A session exists locally but couldn't be verified because the network is
    /// unreachable. RootView shows OfflineGateView and retries on reconnect.
    case restoreFailedOffline
    case failed(String)
    // session / isSignedIn computed vars unchanged
```

`SupabaseAuthService.restoreSession` — classify connectivity failures instead of swallowing them:

```swift
    func restoreSession() async throws -> AuthSession? {
        let client = try requireClient()

        if let stored = client.auth.currentSession, !stored.isExpired {
            do {
                return try await mapSession(using: client, session: stored)
            } catch where NetworkErrorClassifier.isConnectivityFailure(error) {
                throw AuthError.networkUnavailable
            }
        }

        do {
            let session = try await client.auth.session
            guard !session.isExpired else { return nil }
            return try await mapSession(using: client, session: session)
        } catch where NetworkErrorClassifier.isConnectivityFailure(error) {
            throw AuthError.networkUnavailable
        } catch {
            return nil
        }
    }
```

`SupabaseAuthService.signOut` — fall back to local scope on connectivity failure:

```swift
    func signOut() async throws {
        let client = try requireClient()
        await unregisterCurrentDeviceToken(client: client)
        do {
            try await client.auth.signOut()
        } catch where NetworkErrorClassifier.isConnectivityFailure(error) {
            // Revoking the refresh token needs the network; clearing the local
            // session must not. The token dies server-side when it expires.
            try? await client.auth.signOut(scope: .local)
        }
    }
```

`AuthStore` — map the error and never strand sign-out:

```swift
    func restoreSession() async {
        do {
            if let session = try await service.restoreSession() {
                state = .signedIn(session)
            } else {
                state = .signedOut
            }
        } catch let error as AuthError where error == .networkUnavailable {
            state = .restoreFailedOffline
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func signOut() async {
        do {
            try await service.signOut()
        } catch {
            // Local session is cleared best-effort by the service; never strand
            // the user in a failed state over a network blip during sign-out.
        }
        state = .signedOut
    }
```

Also extend `cancelSignIn` to reset from the new case:

```swift
    func cancelSignIn() {
        switch state {
        case .signingIn, .failed, .restoreFailedOffline:
            state = .signedOut
        default:
            break
        }
    }
```

`RootView` — route the state to the existing gate and retry it on reconnect:

```swift
    private var shouldShowOfflineGate: Bool {
        guard requiresNetwork else { return false }
        if auth.state == .restoreFailedOffline { return true }
        return network.hasReceivedUpdate && !network.isConnected
    }
```

In `retryAfterConnectivityRestored()`, retry the restore first:

```swift
    private func retryAfterConnectivityRestored() async {
        guard network.isConnected else { return }
        if auth.state == .restoreFailedOffline {
            await auth.restoreSession()
            await syncSessionState()
            return
        }
        if auth.isSignedIn {
            await onboarding.refresh()
            if onboarding.isComplete {
                await syncBoardState()
                store.restartReactionRealtime()
            }
        }
    }
```

The OfflineGateView retry closure already calls `retryAfterConnectivityRestored()` — no change needed there.

Grep for exhaustive switches over `AuthState` before building: `grep -rn "case .failed" --include="*.swift" "On Board"` and check each `switch` on auth state handles the new case (most use `if case` patterns and are unaffected).

- [ ] **Step 4: Run tests**

Run: `xcodebuild test -scheme "On Board" -destination "platform=iOS Simulator,name=iPhone 16 Pro,OS=18.5" -parallel-testing-enabled NO -only-testing "On BoardTests/AuthRestoreOfflineTests" 2>&1 | tail -10`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add "On Board/Auth/AuthState.swift" "On Board/Auth/AuthStore.swift" "On Board/Auth/SupabaseAuthService.swift" "On Board/Auth/MockAuthService.swift" "On Board/Views/Shared/RootView.swift" "On BoardTests/On_BoardTests.swift"
git commit -m "Route offline session restore to OfflineGateView; make sign-out resilient"
```

---

### Task 5: Staleness-window status refresh + waitlist polling

`refreshIfOnline()` early-returns forever once loaded, so RootView's scenePhase-foreground refresh is a no-op and admin approval is invisible until cold relaunch.

**Files:**
- Modify: `On Board/Onboarding/OnboardingStore.swift`
- Modify: `On Board/Views/Onboarding/OnboardingWaitlistStepView.swift`
- Test: `On BoardTests/On_BoardTests.swift`

**Interfaces:**
- Produces: `OnboardingStore.statusStaleInterval: TimeInterval` (internal, default 60, settable for tests).

- [ ] **Step 1: Failing test** — needs a fetch-counting service; add to the test file:

```swift
@MainActor
struct OnboardingStalenessTests {
    private final class CountingOnboardingService: OnboardingService, @unchecked Sendable {
        let inner = MockOnboardingService()
        nonisolated(unsafe) var fetchCount = 0
        func fetchStatus() async throws -> OnboardingStatus {
            fetchCount += 1
            return try await inner.fetchStatus()
        }
        func checkHandleAvailable(_ handle: String) async throws -> Bool { try await inner.checkHandleAvailable(handle) }
        func lookupSchool(for email: String) async throws -> SchoolMatch? { try await inner.lookupSchool(for: email) }
        func completeUsername(_ handle: String) async throws -> OnboardingStatus { try await inner.completeUsername(handle) }
        func completeProfile(displayName: String, bio: String?, avatarUrl: String?) async throws -> OnboardingStatus {
            try await inner.completeProfile(displayName: displayName, bio: bio, avatarUrl: avatarUrl)
        }
        func beginSchoolEmailVerification(_ email: String) async throws -> OnboardingStatus { try await inner.beginSchoolEmailVerification(email) }
        func completeSchoolEmailVerification(_ email: String, token: String) async throws -> OnboardingStatus {
            try await inner.completeSchoolEmailVerification(email, token: token)
        }
        func joinWaitlist() async throws -> OnboardingStatus { try await inner.joinWaitlist() }
    }
    // NOTE: mirror the real `OnboardingService` protocol exactly — check
    // `On Board/Onboarding/OnboardingService.swift` and adjust signatures if they differ.

    @Test func refreshIfOnlineRefetchesOnceStatusIsStale() async throws {
        let auth = AuthStore(service: MockAuthService())
        _ = try await MockAuthService().signIn(with: .apple)
        await auth.signIn(with: .apple)
        let service = CountingOnboardingService()
        let store = OnboardingStore(service: service, auth: auth, network: NetworkMonitor())

        await store.refreshIfOnline()
        #expect(service.fetchCount == 1)

        // Fresh: no refetch.
        await store.refreshIfOnline()
        #expect(service.fetchCount == 1)

        // Stale: refetch.
        store.statusStaleInterval = 0
        await store.refreshIfOnline()
        #expect(service.fetchCount == 2)
    }
}
```

- [ ] **Step 2: Run to verify failure** — `statusStaleInterval` undefined.

- [ ] **Step 3: Implement in `OnboardingStore`:**

Add near the other stored properties:

```swift
    /// How long a fetched status stays "fresh". `refreshIfOnline()` refetches
    /// past this age so foregrounding the app picks up server-side changes
    /// (e.g. waitlist approval). Settable for tests.
    var statusStaleInterval: TimeInterval = 60
    private var lastFetchedAt: Date?
```

In `refresh(force:)`, replace the early-return:

```swift
        let isFresh = lastFetchedAt.map { Date.now.timeIntervalSince($0) < statusStaleInterval } ?? false
        if !force, !userChanged, loadState == .loaded, status != nil, isFresh {
            return
        }
```

On success (after `loadState = .loaded`): `lastFetchedAt = .now`. In `reset()`: `lastFetchedAt = nil`.

- [ ] **Step 4: Waitlist polling** — in `OnboardingWaitlistStepView`, after `.onAppear { ... }` add:

```swift
        .task(id: hasJoined) {
            // Poll while parked on the waitlist so admin approval flips the app
            // to the board without requiring a relaunch. RootView swaps this
            // view out when status turns complete, cancelling the task.
            guard hasJoined else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(45))
                guard !Task.isCancelled else { break }
                await onboarding.refresh()
            }
        }
```

- [ ] **Step 5: Run tests**

Run: `xcodebuild test -scheme "On Board" -destination "platform=iOS Simulator,name=iPhone 16 Pro,OS=18.5" -parallel-testing-enabled NO -only-testing "On BoardTests/OnboardingStalenessTests" 2>&1 | tail -10`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add "On Board/Onboarding/OnboardingStore.swift" "On Board/Views/Onboarding/OnboardingWaitlistStepView.swift" "On BoardTests/On_BoardTests.swift"
git commit -m "Refetch onboarding status past a staleness window; poll on waitlist screen"
```

---

### Task 6: Remove dev-board fallbacks from live paths

`SampleBoardID.main` is the production "On Board Dev" board. `BoardStore.refresh` falls back to it, and `BoardWeek`'s decoder substitutes it for a missing `board_id` — both silently show the wrong board.

**Files:**
- Modify: `On Board/Store/BoardStore.swift:192`
- Modify: `On Board/Models/BoardWeek.swift:54`
- Test: `On BoardTests/On_BoardTests.swift`

- [ ] **Step 1: Failing test**

```swift
struct BoardWeekDecodingTests {
    @Test func missingBoardIdFailsInsteadOfSubstitutingDevBoard() {
        let json = """
        {"id":"\(UUID().uuidString)","startsAt":"2026-06-29T07:00:00Z","endsAt":"2026-07-06T07:00:00Z","status":"active"}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        #expect(throws: (any Error).self) {
            _ = try decoder.decode(BoardWeek.self, from: Data(json.utf8))
        }
    }
}
```

- [ ] **Step 2: Run to verify failure** — decodes successfully today (fallback), so the test FAILS.

- [ ] **Step 3: Implement**

`BoardWeek.swift:54`:

```swift
        boardId = try container.decode(UUID.self, forKey: .boardId)
```

(The memberwise `init(boardId: UUID = SampleBoardID.main, ...)` default stays — previews/fixtures use it; only wire decoding gets strict.)

`BoardStore.refresh` (line ~192):

```swift
        // Never fall back to the sample/dev board on live paths: no assigned
        // board means there is nothing to fetch yet (waitlisted user).
        guard let boardID = currentBoardId else { return }
        let hasCachedFeed = activeBoardWeek != nil && !posts.isEmpty
```

Check preview/test fixtures still compile: `loadOfflinePreviewData` sets `currentBoard` before any refresh, and mocks construct `BoardWeek` via the memberwise init — unaffected.

- [ ] **Step 4: Run the board suites**

Run: `xcodebuild test -scheme "On Board" -destination "platform=iOS Simulator,name=iPhone 16 Pro,OS=18.5" -parallel-testing-enabled NO -only-testing "On BoardTests/BoardWeekDecodingTests" -only-testing "On BoardTests/BoardStoreTests" 2>&1 | tail -15`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add "On Board/Store/BoardStore.swift" "On Board/Models/BoardWeek.swift" "On BoardTests/On_BoardTests.swift"
git commit -m "Never fall back to the dev board on live paths; strict BoardWeek decoding"
```

---

### Task 7: `list_accessible_boards` RPC + real board list

The app calls `list_accessible_boards` — it doesn't exist in the DB (silent 404), and `BoardListView` only renders `store.currentBoard` anyway.

**Files:**
- Create: `supabase/migrations/<timestamp>_list_accessible_boards.sql` (NOT git-tracked)
- Modify: `On Board/Views/Feed/BoardListView.swift`

**Interfaces:**
- Consumes: `BoardStore.accessibleBoards: [Board]`, `store.setBoard(id:name:)`, `store.refresh(for:)`, `store.currentUserID`.

- [ ] **Step 1: Migration** — file + `apply_migration` (name: `list_accessible_boards`):

```sql
create or replace function public.list_accessible_boards(p_user_id uuid)
returns table (id uuid, name text, created_at timestamptz)
language sql
stable
security definer
set search_path to 'public'
as $$
  select b.id, b.name, b.created_at
  from public.board_members bm
  join public.boards b on b.id = bm.board_id
  where bm.user_id = p_user_id
    and bm.user_id = auth.uid()
  order by b.name;
$$;

revoke execute on function public.list_accessible_boards(uuid) from anon;
grant execute on function public.list_accessible_boards(uuid) to authenticated;
```

Verify with the Supabase MCP `execute_sql`:

```sql
begin;
set local role authenticated;
set local request.jwt.claims to '{"sub":"589a7b14-0a7e-4147-b181-8f7ebe419388","role":"authenticated"}';
select * from public.list_accessible_boards('589a7b14-0a7e-4147-b181-8f7ebe419388');
rollback;
```

Expected: one row — Irvine Valley College.

- [ ] **Step 2: Render accessible boards** — in `BoardListView`, replace the single-board section and wire selection:

```swift
    private var listedBoards: [Board] {
        var boards = store.accessibleBoards
        if let current = store.currentBoard, !boards.contains(where: { $0.id == current.id }) {
            boards.insert(current, at: 0)
        }
        return boards
    }
```

Replace the `List` content:

```swift
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
```

After `.onAppear { ... }` add:

```swift
        .onChange(of: selectedBoardID) { _, newValue in
            guard let newValue,
                  let boardID = UUID(uuidString: newValue),
                  boardID != store.currentBoardId,
                  let board = listedBoards.first(where: { $0.id == boardID }) else { return }
            store.setBoard(id: board.id, name: board.name)
            Task { await store.refresh(for: store.currentUserID) }
        }
```

- [ ] **Step 3: Build check**

Run: `xcodebuild -scheme "On Board" -destination "generic/platform=iOS Simulator" build 2>&1 | grep -E "error:|^\*\* BUILD (SUCCEEDED|FAILED)"`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add "On Board/Views/Feed/BoardListView.swift"
git commit -m "List all accessible boards and switch boards on selection"
```

---

### Task 8: Security settings rework (sections, Linked menu, Change flow)

**Files:**
- Modify: `On Board/Views/Settings/AccountSecuritySettingsView.swift`
- Modify: `On Board/Views/Settings/LinkSignInMethodView.swift`

**Interfaces:**
- Consumes: Task 1's corrected `canUnlinkIdentity(_:)` / `hasLinked(_:)`.
- Produces: `LinkSignInMethodView(mode:intent:onLinked:)` with `enum Intent { case link, change }` (default `.link` keeps the onboarding-time caller compiling if any).

- [ ] **Step 1: `LinkSignInMethodView` gains an intent** — add and thread through the copy:

```swift
    enum Intent {
        case link
        case change
    }

    let mode: Mode
    var intent: Intent = .link
    let onLinked: () -> Void
```

Title: `.navigationTitle(navigationTitle)` with:

```swift
    private var navigationTitle: String {
        switch (mode, intent) {
        case (.phone, .link): "Link Phone"
        case (.email, .link): "Link Email"
        case (.phone, .change): "Change Phone"
        case (.email, .change): "Change Email"
        }
    }
```

Footer + verify-button copy swap "link" for "update" when `intent == .change` (e.g. "We'll text you a code to update the number on your account." / button `LoadingButtonLabel(intent == .change ? "Verify and update" : "Verify and link", ...)`). The auth calls are identical — Supabase's `updateUser` + `phoneChange`/`emailChange` OTP already handles both link and change.

- [ ] **Step 2: Rework `AccountSecuritySettingsView`:**

Split the single section into two:

```swift
        Form {
            traditionalMethodsSection
            thirdPartySection
            // Security placeholders section unchanged
```

```swift
    @ViewBuilder
    private var traditionalMethodsSection: some View {
        Section {
            if let session = auth.session {
                phoneMethodRow(session: session)
                emailMethodRow(session: session)
            } else if isRefreshing {
                ProgressView("Loading sign-in methods…")
            }
        } header: {
            Text("Sign-In Methods")
                .fontStyle(.subheadline)
        } footer: {
            Text("Keep at least one way to sign in.")
                .fontStyle(.footnote)
        }
    }

    @ViewBuilder
    private var thirdPartySection: some View {
        Section {
            if let session = auth.session {
                appleMethodRow(session: session)
                googleMethodRow(session: session)
            }
        } header: {
            Text("Third-Party")
                .fontStyle(.subheadline)
        } footer: {
            Text("To remove Apple or Google, add a phone number, email, or another linked account first.")
                .fontStyle(.footnote)
        }
    }
```

`LinkSheet` carries intent:

```swift
    private enum LinkSheet: Identifiable {
        case phone(LinkSignInMethodView.Intent)
        case email(LinkSignInMethodView.Intent)

        var id: String {
            switch self {
            case .phone: "phone"
            case .email: "email"
            }
        }
    }
```

Sheet construction:

```swift
        .sheet(item: $linkSheet) { sheet in
            switch sheet {
            case .phone(let intent):
                LinkSignInMethodView(mode: .phone, intent: intent) {
                    Task { await refreshMethods() }
                }
            case .email(let intent):
                LinkSignInMethodView(mode: .email, intent: intent) {
                    Task { await refreshMethods() }
                }
            }
        }
```

Update the two "Add" buttons in the `showAddMethodBeforeUnlink` alert to `linkSheet = .phone(.link)` / `.email(.link)`, and `phoneMethodRow`/`emailMethodRow` link actions likewise.

`signInMethodRow` trailing accessory — linked rows get **Change** instead of a bare checkmark:

```swift
            if !isLinked {
                Button("Link", action: linkAction)
                    .fontStyle(.subheadline)
            } else {
                Button("Change", action: changeAction)
                    .fontStyle(.subheadline)
            }
```

with `phoneMethodRow` passing `changeAction: { linkSheet = .phone(.change) }` and email likewise (add a `changeAction: @escaping () -> Void` parameter).

`linkedOAuthRow` — replace the destructive Unlink button with the Linked menu / sole-method state:

```swift
            Spacer(minLength: 8)

            if session.canUnlinkIdentity(identity) {
                Menu {
                    Button("Unlink \(identity.provider.label)", role: .destructive) {
                        identityPendingUnlink = identity
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("Linked")
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2)
                    }
                    .fontStyle(.subheadline)
                    .foregroundStyle(.secondary)
                }
            } else {
                Text("Linked")
                    .fontStyle(.subheadline)
                    .foregroundStyle(.tertiary)
            }
```

For the sole-method case also swap the row subtitle (the email line) for the explanation:

```swift
                if !session.canUnlinkIdentity(identity) {
                    Text("Connect another method to unlink")
                        .fontStyle(.caption)
                        .foregroundStyle(.secondary)
                } else if let email = identity.email ?? session.email, !email.isEmpty {
                    Text(email)
                        .fontStyle(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
```

Replace the `confirmationDialog` with a final alert (menu is now the first stage):

```swift
        .alert(
            "Unlink \(identityPendingUnlink?.provider.label ?? "account")?",
            isPresented: Binding(
                get: { identityPendingUnlink != nil },
                set: { if !$0 { identityPendingUnlink = nil } }
            )
        ) {
            Button("Unlink", role: .destructive) {
                guard let identity = identityPendingUnlink else { return }
                Task { await unlink(identity) }
            }
            Button("Cancel", role: .cancel) { identityPendingUnlink = nil }
        } message: {
            Text("You won't be able to sign in with this method unless you link it again.")
        }
```

`prepareUnlink` and `showUnlinkBlockedAlert` become unreachable via UI (the menu is hidden for sole methods) — keep the `unlink(_:)` server-side `cannotUnlinkLastSignInMethod` catch as the backstop, delete `prepareUnlink` and the now-unused `showUnlinkBlockedAlert` state if nothing references them.

- [ ] **Step 3: Build check**

Run: `xcodebuild -scheme "On Board" -destination "generic/platform=iOS Simulator" build 2>&1 | grep -E "error:|^\*\* BUILD (SUCCEEDED|FAILED)"`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add "On Board/Views/Settings/AccountSecuritySettingsView.swift" "On Board/Views/Settings/LinkSignInMethodView.swift"
git commit -m "Sectioned sign-in methods; guarded Linked menu for unlink; change email/phone flow"
```

---

### Task 9: Full verification pass

- [ ] **Step 1: Full build**

Run: `xcodebuild -scheme "On Board" -destination "generic/platform=iOS Simulator" build 2>&1 | grep -E "error:|^\*\* BUILD (SUCCEEDED|FAILED)"`
Expected: `** BUILD SUCCEEDED **`, zero errors.

- [ ] **Step 2: Full test suite**

Run: `xcodebuild test -scheme "On Board" -destination "platform=iOS Simulator,name=iPhone 16 Pro,OS=18.5" -parallel-testing-enabled NO 2>&1 | tail -25`
Expected: all suites pass, including pre-existing ones.

- [ ] **Step 3: Live verification via Supabase MCP**
  - `execute_sql`: confirm `list_accessible_boards` returns Irvine Valley College for user `589a7b14-0a7e-4147-b181-8f7ebe419388` (query in Task 7).
  - `execute_sql`: `select polname from pg_policy where polrelid = 'storage.objects'::regclass;` — expected: includes `avatars_update` and `post_images_update`.
  - After the user next tests an avatar upload on-device: `select bucket_id, count(*) from storage.objects group by bucket_id;` should show rows.

- [ ] **Step 4: Report** — summarize what changed, what was verified, and the two items the user must test on-device (avatar upload during onboarding, waitlist→board transition).
