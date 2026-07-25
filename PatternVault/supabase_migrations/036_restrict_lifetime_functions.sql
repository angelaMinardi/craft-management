-- 036_restrict_lifetime_functions.sql
--
-- The lifetime-offer functions had an explicit GRANT to `authenticated` (from the
-- lifetime-offer migration) that survived the PUBLIC revoke in 035. The lifetime
-- SKU was removed and nothing in the app calls these, so restrict them to
-- service_role only. (AUDIT.md P1-4.)
revoke execute on function public.record_lifetime_purchase() from authenticated;
revoke execute on function public.expire_lifetime_offer_if_past_end_date() from authenticated;
