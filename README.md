# On Board (iOS)

A campus bulletin board for weekly posts, reactions, and comments. Built with SwiftUI and Supabase. Students join a weekly board, post anonymously, react, and comment — the board clears every Monday at midnight.

## Requirements

- Xcode 16+ (iOS 18 minimum deployment target)
- Optional: [Supabase CLI](https://supabase.com/docs/guides/cli) for database migrations

## Getting started

1. Clone the repo and open `On Board.xcodeproj` in Xcode.
2. Select the **On Board** scheme and run on a simulator or device.

The app runs in **mock mode** without any backend keys: auth, onboarding, and board previews all work offline. A live Supabase backend is required for real posts, comments, and push notifications.

### Live Supabase backend (maintainers)

1. Copy the secrets template:

   ```bash
   cp Secrets.xcconfig.example Secrets.xcconfig
   ```

2. Fill in `Secrets.xcconfig` with your project URL and anon key (never commit this file).

3. Apply migrations to your Supabase project:

   ```bash
   supabase login
   supabase link --project-ref YOUR_PROJECT_REF
   supabase db push
   ```

4. In the Supabase Dashboard, enable **Realtime** for the `reactions` table (Database → Publications → `supabase_realtime`).

5. Configure auth providers in the Supabase Dashboard:
   - **Phone** (SMS OTP) — primary sign-in method
   - **Email** (magic link / OTP) — secondary sign-in method
   - **Apple** — native Sign in with Apple (capability already enabled in `On Board.entitlements`)
   - **Google** — enable the Google provider; uses Supabase OAuth in a browser sheet
   - Under **Authentication → URL Configuration**, add redirect URL: `onboard://auth-callback`
   - Enable **manual linking** to let users attach Apple/Google to an existing phone or email account

6. Configure push notifications:
   - In **Project Settings → Edge Functions**, add secrets: `APNS_KEY`, `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_BUNDLE_ID`, and `CRON_SECRET`
   - Deploy the Edge Function: `supabase functions deploy send-notifications`
   - Set up the four `pg_cron` jobs via the SQL Editor (see `CLAUDE.md` for schedules)
   - For App Store distribution, change `api.sandbox.push.apple.com` → `api.push.apple.com` in the Edge Function

## Project layout

| Path | Purpose |
|------|---------|
| `On Board/` | SwiftUI app source |
| `On Board/Auth/` | Auth state machine, providers, sign-in coordinators |
| `On Board/Notifications/` | APNs registration, device token upload, last-seen tracking |
| `On Board/Onboarding/` | Onboarding flow and step views |
| `On Board/Store/` | BoardStore — posts, reactions, comments |
| `On Board/Supabase/` | Supabase service implementations and JSON adapters |
| `On Board/Views/` | All SwiftUI views |
| `Styling/` | Shared fonts, button styles, navigation chrome |
| `supabase/migrations/` | Ordered SQL migrations (source of truth for schema) |
| `Secrets.xcconfig.example` | Template for local API keys |

## Database

Migrations live in `supabase/migrations/` and must be applied in filename order. Use `supabase db push` on a linked project. Never edit migration files after they've been applied to a shared environment — add a new file instead.

## Fonts

The app bundles **Zalando Sans** under `Styling/Font/`. Confirm you have redistribution rights before making the repository public.

## Contributing

- Do not commit `Secrets.xcconfig`, `.env` files, or `supabase/.temp/`.
- SQL changes belong in new timestamped files under `supabase/migrations/`.
- Without Supabase keys, contributors can build and test auth/onboarding UI against mocks. Board data and push notifications require live backend keys.
- Push notification delivery requires a physical device — the Simulator cannot receive APNs.

## License

Add your license here before making the repository public.
