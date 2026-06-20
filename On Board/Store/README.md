# Store layer

Supabase is the source of truth. `BoardStore` is a **session cache** — it holds
the current fetch, the signed-in user's reactions/votes, and optimistic updates
while mutations are in flight.

| File | Role |
|------|------|
| `BoardStore.swift` | Cache, refresh, feed composition, lookups |
| `BoardStore+Interactions.swift` | Post/profile mutations, reactions, comment votes |
| `BoardStore+Preview.swift` | `sampleBoard()` / `previewBoard()` fixtures for SwiftUI previews |

**Live path:** `RootView` → `configure` → `refresh(for:)` → `BoardService` (Supabase RPCs).

**Offline path:** When Supabase is not configured, `loadOfflinePreviewData()` seeds
sample posts with a synthetic active week so the UI remains usable for development.

There is no on-device persistence of boards beyond this in-memory session.
