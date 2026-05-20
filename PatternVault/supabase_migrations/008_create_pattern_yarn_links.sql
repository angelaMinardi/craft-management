-- Corvid Craft Migration 008: Create pattern_yarn_links table
-- Run this in Supabase Dashboard -> SQL Editor -> New query -> paste -> Run
--
-- Stores AI-extracted yarn brand links (official site, store) per pattern.

CREATE TABLE IF NOT EXISTS public.pattern_yarn_links (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    pattern_id uuid REFERENCES public.patterns(id) ON DELETE CASCADE NOT NULL,
    user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    brand_name text NOT NULL,
    official_url text,
    store_url text,
    display_order integer NOT NULL DEFAULT 0,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_pattern_yarn_links_pattern ON public.pattern_yarn_links(pattern_id);
CREATE INDEX IF NOT EXISTS idx_pattern_yarn_links_user ON public.pattern_yarn_links(user_id);

ALTER TABLE public.pattern_yarn_links ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own pattern yarn links"
    ON public.pattern_yarn_links FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own pattern yarn links"
    ON public.pattern_yarn_links FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete their own pattern yarn links"
    ON public.pattern_yarn_links FOR DELETE
    USING (auth.uid() = user_id);
