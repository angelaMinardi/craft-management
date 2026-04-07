-- Pattern Vault Migration 012: User entitlements and usage (freemium)
-- Run in Supabase Dashboard → SQL Editor → New query → paste → Run
--
-- Tracks subscription status and monthly usage for free-tier limits.
-- Limits: 30 patterns (enforced in app by count), 5 AI/month, 3 YouTube/month, 20 note photos (enforced in app by count).

CREATE TABLE IF NOT EXISTS public.user_entitlements (
    user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    is_premium boolean NOT NULL DEFAULT false,
    ai_usage_this_month integer NOT NULL DEFAULT 0,
    youtube_imports_this_month integer NOT NULL DEFAULT 0,
    usage_month text NOT NULL DEFAULT to_char(now(), 'YYYY-MM'),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_user_entitlements_usage_month ON public.user_entitlements(usage_month);

DROP TRIGGER IF EXISTS user_entitlements_updated_at ON public.user_entitlements;
CREATE TRIGGER user_entitlements_updated_at
    BEFORE UPDATE ON public.user_entitlements
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.user_entitlements ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own entitlements"
    ON public.user_entitlements FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can update own entitlements (for is_premium from app/StoreKit)"
    ON public.user_entitlements FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "Users can insert own entitlements (upsert on first use)"
    ON public.user_entitlements FOR INSERT WITH CHECK (auth.uid() = user_id);

-- RPC: Ensure row exists for user and return current usage (for current month; resets if new month).
CREATE OR REPLACE FUNCTION public.get_or_create_usage(p_user_id uuid)
RETURNS public.user_entitlements
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    current_month text := to_char(now(), 'YYYY-MM');
    row public.user_entitlements;
BEGIN
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
$$;

-- RPC: Increment AI usage if under limit (or premium). Returns new count or -1 if denied.
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
BEGIN
    row := public.get_or_create_usage(p_user_id);
    IF row.usage_month <> current_month THEN
        row := (SELECT public.get_or_create_usage(p_user_id));
    END IF;
    IF row.is_premium THEN
        new_count := row.ai_usage_this_month + 1;
    ELSIF row.ai_usage_this_month >= 5 THEN
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

-- RPC: Increment YouTube imports if under limit (or premium). Returns new count or -1 if denied.
CREATE OR REPLACE FUNCTION public.increment_youtube_imports(p_user_id uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    row public.user_entitlements;
    current_month text := to_char(now(), 'YYYY-MM');
    new_count integer;
BEGIN
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
$$;

-- RPC for Edge Function: no args, uses auth.uid(). Returns new count or -1 if denied.
CREATE OR REPLACE FUNCTION public.increment_youtube_imports_for_current_user()
RETURNS integer
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.increment_youtube_imports(auth.uid());
$$;

GRANT EXECUTE ON FUNCTION public.increment_youtube_imports_for_current_user() TO authenticated;

-- RPC: Count project notes with a photo for the user (for freemium note-photo limit).
CREATE OR REPLACE FUNCTION public.count_notes_with_photo(p_user_id uuid)
RETURNS integer
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT count(*)::integer FROM public.project_notes WHERE user_id = p_user_id AND photo_url IS NOT NULL;
$$;
GRANT EXECUTE ON FUNCTION public.count_notes_with_photo(uuid) TO authenticated;

-- Allow authenticated users to call these RPCs (they take their own user_id).
GRANT EXECUTE ON FUNCTION public.get_or_create_usage(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.increment_ai_usage(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.increment_youtube_imports(uuid) TO authenticated;
