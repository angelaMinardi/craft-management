-- 035_revoke_execute_from_public.sql
--
-- Corrects 033: `REVOKE ... FROM anon` did NOT remove anon's access, because
-- Postgres grants EXECUTE to the PUBLIC pseudo-role by default on every
-- CREATE OR REPLACE FUNCTION, and PUBLIC includes anon. The advisor kept flagging
-- these as anon-executable. The fix is to revoke from PUBLIC, then grant EXECUTE
-- back only to the roles that should have it. Non-breaking: the app, Share
-- Extension, and edge functions all call these as `authenticated`.
-- (AUDIT.md P0-2, P1-4.)

-- User-scoped RPCs the app/extension/edge functions legitimately call.
revoke execute on function public.increment_ai_usage(uuid) from public;
grant execute on function public.increment_ai_usage(uuid) to authenticated;

revoke execute on function public.increment_youtube_imports(uuid) from public;
grant execute on function public.increment_youtube_imports(uuid) to authenticated;

revoke execute on function public.increment_youtube_imports_for_current_user() from public;
grant execute on function public.increment_youtube_imports_for_current_user() to authenticated;

revoke execute on function public.get_or_create_usage(uuid) from public;
grant execute on function public.get_or_create_usage(uuid) to authenticated;

revoke execute on function public.count_notes_with_photo(uuid) from public;
grant execute on function public.count_notes_with_photo(uuid) to authenticated;

-- Dead lifetime-offer functions (lifetime SKU removed; no app references).
-- Restrict to server-side only.
revoke execute on function public.record_lifetime_purchase() from public;
grant execute on function public.record_lifetime_purchase() to service_role;

revoke execute on function public.expire_lifetime_offer_if_past_end_date() from public;
grant execute on function public.expire_lifetime_offer_if_past_end_date() to service_role;

-- Trigger function; never needs to be REST-callable.
revoke execute on function public.set_updated_at() from public;
