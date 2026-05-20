-- Corvid Craft Migration 030: Server-enforced premium AI soft cap
-- Run in Supabase Dashboard → SQL Editor → New query → paste → Run
--
-- Adds a 200/month soft cap for premium users on the AI usage RPC. Keeps Gemini
-- costs bounded at ~$1/user/month worst case. Free tier limit (5/mo) is unchanged.
-- Fair-use policy note: the client surfaces a friendly notice at the cap, not a hard error.

CREATE OR REPLACE FUNCTION public.increment_ai_usage(p_user_id uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    row public.user_entitlements;
    current_month text := to_char(now(), 'YYYY-MM');
    new_count integer;
    free_cap constant integer := 5;
    premium_soft_cap constant integer := 200;
BEGIN
    row := public.get_or_create_usage(p_user_id);
    IF row.usage_month <> current_month THEN
        row := (SELECT public.get_or_create_usage(p_user_id));
    END IF;

    IF row.is_premium THEN
        IF row.ai_usage_this_month >= premium_soft_cap THEN
            -- Soft cap hit. Return -1 so client can surface fair-use notice.
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
$$;

GRANT EXECUTE ON FUNCTION public.increment_ai_usage(uuid) TO authenticated;
