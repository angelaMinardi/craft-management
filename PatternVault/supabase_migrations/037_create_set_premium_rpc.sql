-- 037_create_set_premium_rpc.sql
--
-- SAFE TO APPLY NOW (additive). Creates the set_premium RPC that the updated app
-- (EntitlementRepository.setPremium) calls instead of writing is_premium directly.
-- The currently-shipped build (which writes is_premium directly) ignores this RPC,
-- so adding it is non-breaking for old and new builds alike.
--
-- The column-lock trigger that actually *enforces* this (and would break the old
-- build) lives in 034 and is applied separately, once the old build is retired.
-- (AUDIT.md P0-2.)

create or replace function public.set_premium(p_is_premium boolean)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;
    PERFORM public.get_or_create_usage(auth.uid());
    UPDATE public.user_entitlements
    SET is_premium = p_is_premium, updated_at = now()
    WHERE user_id = auth.uid();
END;
$function$;

-- Revoke from PUBLIC *and* anon: Supabase default privileges grant EXECUTE to anon
-- on newly created public functions, which a bare `from public` would leave behind.
revoke execute on function public.set_premium(boolean) from public, anon;
grant execute on function public.set_premium(boolean) to authenticated;
