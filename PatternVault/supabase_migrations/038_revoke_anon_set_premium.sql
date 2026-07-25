-- 038_revoke_anon_set_premium.sql
--
-- Corrects 037: Supabase default privileges auto-grant EXECUTE to anon/authenticated
-- on newly created public functions, so `REVOKE ... FROM public` in 037 left an
-- explicit anon grant on set_premium. Not exploitable (set_premium RAISEs when
-- auth.uid() is null), but revoke it for least privilege / to clear the advisor.
revoke execute on function public.set_premium(boolean) from anon;
