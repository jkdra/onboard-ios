# Launch Readiness Checklist

- **Date:** 2026-08-05
- **State when written:** 1.1.1 (build 2) merged to `main` and pushed, not yet
  archived/submitted. Waitlist gated; ~15 users, all known. Primary launch
  campus: Irvine Valley College.
- Items marked **[you]** need Jawad (dashboard access, signing, or a real
  device). Items marked **[claude]** can be done in a session once their
  blocker clears.

## 1 · Submit 1.1.1 — everything else queues behind this

- [ ] **[you]** Archive from `main` (`4ca2f00` or later) in Xcode.
- [ ] **[you]** Before uploading: confirm the archive is NOT in mock mode —
      `Secrets.xcconfig` present, `AppConfiguration.isSupabaseConfigured` true.
      A build missing the anon key ships silently on sample data.
- [ ] **[you]** Submit for review.
- [ ] **[you]** Turn on **phased release** in App Store Connect (one toggle,
      free staged rollout of the binary for auto-updating users).

## 2 · While review runs (1–2 days of free parallel time)

- [ ] **[you]** Deploy the admin portal: `wrangler login` (or set
      `CLOUDFLARE_API_TOKEN`), then `npm run cf:deploy` in `onboard-admin`.
      Until this, the Config page and Campus Demand card exist only locally,
      and incident response is still hand-written SQL.
- [ ] **[you]** Sentry: `brew install getsentry/tools/sentry-wizard &&
      sentry-wizard -i ios`, hand over the DSN.
      **[claude]** Then Plan C (`2026-08-03-observability.md`) lands same-day:
      crash + non-fatal capture, flag-set tagging, PII scrubbing. This is the
      only *detect* signal we have planned; every rollout lever built this
      month is currently flying blind without it.
- [ ] **[you]** Confirm **Auth SMTP is Resend** (Supabase dashboard → Auth →
      SMTP). Flagged as a launch blocker on 2026-07-23 and never confirmed
      since. The editable 100/h email rate limit suggests custom SMTP is set,
      but suggests ≠ confirmed.
- [ ] **[you]** Check the **per-user OTP resend interval** (Auth → Providers →
      Email and Phone, "minimum interval between sends"). The app's resend
      button now enables at 30s everywhere. If the provider interval is 60s,
      either lower it to 30s or say the word and `otp_cooldown_seconds=60`
      gets seeded — one row, no build.
- [ ] **[you]** Decide on **leaked-password protection** (Auth → HIBP toggle).
      Passwords are still offered via SetPasswordView; this has been on the
      release checklist since July.

## 3 · Once 1.1.1 is live (before opening anything)

- [ ] **[you]** Update your own device, do one real sign-in + post + resend.
- [ ] **[claude]** Verify telemetry landed:
      `select app_version, count(*) from device_tokens group by 1` shows 1.1.1.
- [ ] **[claude]** Canary the config path in production: seed
      `feed_poll_seconds=120`, confirm via the in-app inspector
      (Settings → Remote Config [DEV] — debug builds only), delete it.
- [ ] **[claude]** Seed all four flags at `on` (matching current behavior) so
      the flag path is exercised in production before it's ever needed at `off`.

## 4 · Before the QR code goes up at IVC

Rate limits (Supabase → Auth → Rate Limits) — the current per-IP values assume
one person per IP; campus WiFi NAT puts hundreds behind a few:

- [ ] **[you]** Token verifications: 30 → **150–200 / 5 min** (per IP).
- [ ] **[you]** Sign-ups & sign-ins: 30 → **~100 / 5 min** (per IP).
- [ ] **[you]** SMS: 30/h project-wide → **hundreds/h** (phone is the default
      sign-in; a good tabling hour exhausts 30, and resends count). Confirm the
      SMS provider's own throughput supports whatever is set.
- [ ] Token refreshes (150/5min): fine initially; same NAT class — watch it.

Other pre-open checks:

- [ ] **[you]** TestFlight the launch build past the friend group once.
- [ ] **[claude]** Final advisor sweep + confirm every `notify_push` trigger
      still has a `case` in the deployed `send-notifications` switch.
- [ ] **[you]** Carry a **debug build** on your own phone at the launch table —
      the Remote Config inspector is compiled out of release builds, and it's
      the fastest "what is this device actually resolving?" tool if anything
      looks wrong live.

## 5 · Launch-day operating loop

- Admin Home (deployed) = waitlist + Campus Demand + audit trail.
- Sentry (if landed) = crash-free rate per version; the stop signal.
- The kill switches, in the order they'd plausibly be pulled:
  `flag_postPhotoAttachments` (upload/moderation incident) →
  `enabled_reactions` without `dislike` (pile-on) →
  `flag_zoomTransition` / `flag_glassEffects` (rendering weirdness) →
  `feed_poll_seconds` up (DB load) →
  `recommended_version` (bad build, soft) → `min_supported_version` (bad
  build, hard — locks people out; last resort).
- Admission stays manual per user — the strongest throttle in the system.

## Explicitly deferred (not launch work)

First Class + ads (`feature/monetization`), Groups, passkeys (server toggle on
is fine; app adoption waits for the beta/SPI labels to drop), the
accept-unknown-.edu limbo state (the demand ledger decides when), UI-test
harness (re-check per Xcode release), remaining `../supabase` remote setup.
