# On Board

![Platform](https://img.shields.io/badge/platform-iOS%2018%2B-black?logo=apple&logoColor=white)
![Swift](https://img.shields.io/badge/Swift-6.2-F05138?logo=swift&logoColor=white)
![Supabase](https://img.shields.io/badge/Supabase-2.46-3ECF8E?logo=supabase&logoColor=white)
![License](https://img.shields.io/badge/license-All%20Rights%20Reserved-red)

A campus bulletin board for iOS. Students post to a shared board that resets every Monday at midnight — one week, one community, then gone.

## What it does

Every week, a fresh board opens for a school campus. Anyone who's joined can post a short note, react to others' posts, and leave comments. At midnight on Monday the board clears and a new one begins.

**Core loop:**
- Sign in with phone, email, Apple, or Google
- Complete a one-time onboarding: pick a handle, verify your school email, join the waitlist if your campus isn't live yet
- Post anonymously to the active board — your handle is visible, but nothing else ties back to you
- React (like, hug, laugh, or spark) and comment in threaded replies
- Watch the countdown — when it hits zero, everything resets

## How it's built

**SwiftUI + Supabase.** The app targets iOS 18 and uses iOS 26 APIs (liquid glass, etc.) where available with graceful fallbacks.

Auth supports phone OTP, email magic link, Sign in with Apple, and Google Sign-In. Multiple providers can be linked to a single account, with guardrails that prevent unlinking your last sign-in method.

Board data is fetched via Supabase RPC and kept in an in-memory store. Reactions update in real time via a Supabase Realtime subscription. All mutations are applied optimistically and rolled back on error.

Push notifications fire on four schedules: a Monday reset announcement, mid-week re-engagement for users who haven't seen new posts, a Sunday nudge, and a "clearing soon" alert in the final hours before reset.

Onboarding is a linear state machine: handle → profile → school email verification → waitlist (if applicable) → done. Users who signed in with Apple or Google before picking a handle are detected and routed back through the username step automatically.

## Code structure

```
On Board/          SwiftUI app
  Auth/            Sign-in flow, session management, provider linking
  Store/           BoardStore — posts, reactions, comments, realtime
  Onboarding/      Onboarding state machine and step views
  Notifications/   APNs registration and push scheduling
  Supabase/        Network layer, JSON decoders, RPC calls
  Views/           All SwiftUI views
  Models/          Data types
  Utilities/       Board schedule math, phone normalizer, handle rules
Styling/           Shared fonts, button styles, nav chrome
supabase/
  migrations/      SQL schema (source of truth)
  functions/       Edge Functions for push notification delivery
On BoardTests/     Swift Testing unit tests
```

## License

All rights reserved. This code is public for reference only — not for reuse or redistribution.
