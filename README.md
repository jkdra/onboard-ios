# On Board (iOS)

A campus bulletin board for weekly posts, reactions, and onboarding. Built with SwiftUI and Supabase.

## Requirements

- Xcode 16+ (iOS 18 deployment target)
- Optional: [Supabase CLI](https://supabase.com/docs/guides/cli) for database migrations

## Getting started

1. Clone the repo and open `On Board.xcodeproj` in Xcode.
2. Select the **On Board** scheme and run on a simulator or device.

The app runs in **development mode** without any backend keys: mock auth, sample board data, and full onboarding UI.

### Live Supabase backend (maintainers)

1. Copy the secrets template:

   ```bash
   cp Secrets.xcconfig.example Secrets.xcconfig
   ```

2. Fill in `Secrets.xcconfig` with your project URL and anon key (never commit this file).

3. Link Supabase and apply migrations:

   ```bash
   supabase login
   supabase link --project-ref YOUR_PROJECT_REF
   ./supabase/apply_migrations.sh
   ```

4. In the Supabase Dashboard, enable **Realtime** for the `reactions` table (Database → Publications → `supabase_realtime`) if it is not already enabled after migration.

5. Configure auth providers you use (Phone, Apple Sign In, etc.) in the Supabase Dashboard.

## Project layout

| Path | Purpose |
|------|---------|
| `On Board/` | SwiftUI app — auth, onboarding, feed, archive |
| `Styling/` | Shared fonts, button styles, navigation chrome |
| `Configuration/` | Xcode build settings (`Project.xcconfig`) |
| `supabase/migrations/` | Ordered SQL migrations (source of truth for schema changes) |
| `supabase/schema.sql` | Full schema reference snapshot (do not run on an existing DB) |
| `Secrets.xcconfig.example` | Template for local API keys |

## Database

- Migrations live in `supabase/migrations/` and should be applied in filename order.
- Prefer `supabase db push` (via `./supabase/apply_migrations.sh`) on a linked project.
- `supabase/.temp/` is machine-local CLI state and is gitignored.

## Fonts

The app bundles **Zalando Sans** under `Styling/Font/`. Confirm you have redistribution rights before publishing the repo publicly.

## Contributing

- Do not commit `Secrets.xcconfig`, `.env` files, or `supabase/.temp/`.
- SQL changes belong in new timestamped files under `supabase/migrations/`.
- Without Supabase keys, contributors can still build and test against mock data.

## License

Add your license here before making the repository public.
