-- 034_lock_entitlement_columns.sql
--
-- ⚠️ APPLY THIS ONLY AFTER THE OLD BUILD IS RETIRED (made the minimum supported
--    version). NOT BEFORE.
--
-- This trigger blocks client roles from changing is_premium / usage columns
-- directly, forcing all writes through SECURITY DEFINER RPCs (set_premium — see
-- migration 037 — and the increment_* usage RPCs). The currently-shipped build
-- writes is_premium with a direct table UPDATE (EntitlementRepository.setPremium);
-- once this trigger is live that write silently no-ops, so a paying user on the
-- OLD build would have their server-side AI cap stuck at the free tier until they
-- update. Ship the app build that calls set_premium (037) first, then apply this.
--
-- Addresses AUDIT.md P0-2 (client-writable entitlement). set_premium RPC: see 037.

-- Trigger: server-managed columns can't be changed by the client roles. SECURITY
-- INVOKER (default) so current_user reflects the real caller — 'authenticated' /
-- 'anon' for a PostgREST request, but the function owner (postgres) inside a
-- SECURITY DEFINER RPC, which is therefore allowed through. service_role bypasses.
create or replace function public.protect_entitlement_columns()
returns trigger
language plpgsql
set search_path to 'public'
as $function$
BEGIN
    IF current_user IN ('authenticated', 'anon') THEN
        NEW.is_premium := OLD.is_premium;
        NEW.ai_usage_this_month := OLD.ai_usage_this_month;
        NEW.youtube_imports_this_month := OLD.youtube_imports_this_month;
        NEW.usage_month := OLD.usage_month;
    END IF;
    RETURN NEW;
END;
$function$;

-- Trigger functions are never called over REST; strip the default anon/PUBLIC grant.
revoke execute on function public.protect_entitlement_columns() from public, anon;

drop trigger if exists protect_entitlement_columns_trg on public.user_entitlements;
create trigger protect_entitlement_columns_trg
    before update on public.user_entitlements
    for each row execute function public.protect_entitlement_columns();
