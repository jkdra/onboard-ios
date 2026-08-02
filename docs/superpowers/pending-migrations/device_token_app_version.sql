-- STAGED, NOT APPLIED. Needs your explicit go-ahead.
--
-- Why this one is held back while everything else in the branch is live:
-- it drops and recreates `register_device_token`, which the SHIPPED 1.1 app
-- calls on every push registration. The change is low risk (the new signature
-- defaults p_app_version, so a one-argument call from 1.1 still resolves) and
-- the drop+create is atomic inside the migration — but if it is wrong, push
-- registration breaks for live users, and it was applied while nobody was
-- awake to notice. That is not a trade worth making unattended.
--
-- Everything else this branch needs (get_app_config) is additive and is
-- already applied.
--
-- To apply: hand this to the Supabase MCP `apply_migration` with name
-- `device_token_app_version`, then verify with the checks at the bottom.

-- Record which app version each device is running, so a staged rollout or a
-- min-version gate can be reasoned about before it is relied on. Without this
-- there is no way to answer "what share of users can even read my config?".
alter table public.device_tokens add column if not exists app_version text;

-- The parameter list changes, so this is a drop + create rather than a replace.
-- p_app_version defaults to null, so a client still making the one-argument
-- call (i.e. everything currently in the field) keeps working unchanged.
drop function if exists public.register_device_token(text);

create function public.register_device_token(
  p_token text,
  p_app_version text default null
)
returns void
language sql
security definer
set search_path to 'public'
as $$
  insert into device_tokens (user_id, token, app_version, updated_at)
  values (auth.uid(), p_token, p_app_version, now())
  on conflict (token)
  do update set user_id = auth.uid(),
                -- coalesce so an older client sending null cannot wipe a
                -- version a newer client already recorded for this device.
                app_version = coalesce(excluded.app_version, device_tokens.app_version),
                updated_at = now();
$$;

revoke all on function public.register_device_token(text, text) from public;
grant execute on function public.register_device_token(text, text) to authenticated;

-- Verify after applying:
--
--   select column_name from information_schema.columns
--    where table_schema='public' and table_name='device_tokens'
--      and column_name='app_version';
--   -- expect: one row
--
--   select proname, pg_get_function_identity_arguments(oid)
--     from pg_proc where proname='register_device_token';
--   -- expect: exactly one row, args "p_token text, p_app_version text"
--
-- Then confirm push still registers on a real device before shipping 1.1.1.
--
-- The matching client change (one line in NotificationService.upload, sending
-- "p_app_version": AppVersion.current alongside p_token) is NOT in the branch
-- either — it would fail against the current one-argument function. Add it in
-- the same sitting as this migration.
