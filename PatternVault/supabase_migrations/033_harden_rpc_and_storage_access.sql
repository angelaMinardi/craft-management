-- 033_harden_rpc_and_storage_access.sql
--
-- NON-BREAKING hardening — safe to apply to the live project immediately.
-- Addresses AUDIT.md P0-1 (storage listing), P0-2 (RPC caller check / anon abuse),
-- P1-4 (over-exposed SECURITY DEFINER functions), and P3-5 (mutable search_path).
--
-- What it does NOT do: lock the is_premium / usage columns from direct client
-- writes — that is in 034 and must ship WITH the next app build (the shipped app
-- still writes is_premium directly). See 034 header.

-- 1) Storage: remove the broad public SELECT policies that let anyone LIST every
--    object in these buckets. Public buckets still serve files by URL without a
--    SELECT policy, so this is non-breaking for image/PDF display.
drop policy if exists "Pattern PDFs read" on storage.objects;
drop policy if exists "Pattern images read" on storage.objects;
drop policy if exists "Public read access for note photos" on storage.objects;

-- 2) Usage RPCs: assert the caller is the target user. The app and Share Extension
--    always pass their own id while authenticated, so this is non-breaking, but it
--    stops anyone from exhausting another user's quota via increment_*(victim_id).
create or replace function public.increment_ai_usage(p_user_id uuid)
returns integer
language plpgsql
security definer
set search_path to 'public'
as $function$
DECLARE
    row public.user_entitlements;
    current_month text := to_char(now(), 'YYYY-MM');
    new_count integer;
    free_cap constant integer := 5;
    premium_soft_cap constant integer := 200;
BEGIN
    IF auth.uid() IS NULL OR auth.uid() <> p_user_id THEN
        RAISE EXCEPTION 'Not authorized';
    END IF;

    row := public.get_or_create_usage(p_user_id);
    IF row.usage_month <> current_month THEN
        row := (SELECT public.get_or_create_usage(p_user_id));
    END IF;

    IF row.is_premium THEN
        IF row.ai_usage_this_month >= premium_soft_cap THEN
            RETURN -1;
        END IF;
        new_count := row.ai_usage_this_month + 1;
    ELSIF row.ai_usage_this_month >= free_cap THEN
        RETURN -1;
    ELSE
        new_count := row.ai_usage_this_month + 1;
    END IF;

    UPDATE public.user_entitlements
    SET ai_usage_this_month = new_count, updated_at = now()
    WHERE user_id = p_user_id;
    RETURN new_count;
END;
$function$;

create or replace function public.increment_youtube_imports(p_user_id uuid)
returns integer
language plpgsql
security definer
set search_path to 'public'
as $function$
DECLARE
    row public.user_entitlements;
    current_month text := to_char(now(), 'YYYY-MM');
    new_count integer;
BEGIN
    IF auth.uid() IS NULL OR auth.uid() <> p_user_id THEN
        RAISE EXCEPTION 'Not authorized';
    END IF;

    row := public.get_or_create_usage(p_user_id);
    IF row.usage_month <> current_month THEN
        row := (SELECT public.get_or_create_usage(p_user_id));
    END IF;
    IF row.is_premium THEN
        new_count := row.youtube_imports_this_month + 1;
    ELSIF row.youtube_imports_this_month >= 3 THEN
        RETURN -1;
    ELSE
        new_count := row.youtube_imports_this_month + 1;
    END IF;
    UPDATE public.user_entitlements
    SET youtube_imports_this_month = new_count, updated_at = now()
    WHERE user_id = p_user_id;
    RETURN new_count;
END;
$function$;

create or replace function public.get_or_create_usage(p_user_id uuid)
returns user_entitlements
language plpgsql
security definer
set search_path to 'public'
as $function$
DECLARE
    current_month text := to_char(now(), 'YYYY-MM');
    row public.user_entitlements;
BEGIN
    IF auth.uid() IS NULL OR auth.uid() <> p_user_id THEN
        RAISE EXCEPTION 'Not authorized';
    END IF;

    SELECT * INTO row FROM public.user_entitlements WHERE user_id = p_user_id;
    IF row IS NULL THEN
        INSERT INTO public.user_entitlements (user_id, usage_month)
        VALUES (p_user_id, current_month)
        RETURNING * INTO row;
        RETURN row;
    END IF;
    IF row.usage_month <> current_month THEN
        UPDATE public.user_entitlements
        SET ai_usage_this_month = 0, youtube_imports_this_month = 0, usage_month = current_month
        WHERE user_id = p_user_id
        RETURNING * INTO row;
    END IF;
    RETURN row;
END;
$function$;

-- count_notes_with_photo previously trusted its p_user_id argument (any signed-in
-- user could read another user's count). Scope it to the caller via auth.uid();
-- the p_user_id argument is retained for signature compatibility but ignored.
create or replace function public.count_notes_with_photo(p_user_id uuid)
returns integer
language sql
security definer
set search_path to 'public'
as $function$
  SELECT count(*)::integer
  FROM public.project_notes
  WHERE user_id = auth.uid() AND photo_url IS NOT NULL;
$function$;

-- 3) Pin the shared trigger function's search_path (advisor 0011).
create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path to ''
as $function$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$function$;

-- 4) Revoke anon EXECUTE on SECURITY DEFINER functions. The app, Share Extension,
--    and edge functions all call these as an authenticated user, so removing the
--    anon grant is non-breaking and closes the unauthenticated attack surface.
revoke execute on function public.increment_ai_usage(uuid) from anon;
revoke execute on function public.increment_youtube_imports(uuid) from anon;
revoke execute on function public.increment_youtube_imports_for_current_user() from anon;
revoke execute on function public.get_or_create_usage(uuid) from anon;
revoke execute on function public.count_notes_with_photo(uuid) from anon;
revoke execute on function public.record_lifetime_purchase() from anon;
revoke execute on function public.expire_lifetime_offer_if_past_end_date() from anon;
revoke execute on function public.set_updated_at() from anon, authenticated;
