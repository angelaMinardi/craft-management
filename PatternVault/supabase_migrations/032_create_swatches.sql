-- Corvid Craft Migration 032: Swatch library
-- Users can log knit/crochet swatches with a photo, the needles/yarn used, and gauge.
-- Run in Supabase Dashboard → SQL Editor → New query → paste → Run.

CREATE TABLE IF NOT EXISTS public.swatches (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    title text,
    craft text,
    photo_url text,
    needle_size text,
    needle_hook_id uuid REFERENCES public.needle_hook_inventory(id) ON DELETE SET NULL,
    yarn_name text,
    yarn_stash_id uuid REFERENCES public.yarn_stash(id) ON DELETE SET NULL,
    stitches_per_4in real,
    rows_per_4in real,
    stitch_pattern text,
    blocked boolean NOT NULL DEFAULT false,
    washed boolean NOT NULL DEFAULT false,
    notes text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_swatches_user ON public.swatches(user_id);
CREATE INDEX IF NOT EXISTS idx_swatches_yarn_stash ON public.swatches(yarn_stash_id) WHERE yarn_stash_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_swatches_needle_hook ON public.swatches(needle_hook_id) WHERE needle_hook_id IS NOT NULL;

DROP TRIGGER IF EXISTS swatches_updated_at ON public.swatches;
CREATE TRIGGER swatches_updated_at
    BEFORE UPDATE ON public.swatches
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.swatches ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own swatches"
    ON public.swatches FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can insert their own swatches"
    ON public.swatches FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can update their own swatches"
    ON public.swatches FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "Users can delete their own swatches"
    ON public.swatches FOR DELETE USING (auth.uid() = user_id);

-- Storage bucket for swatch photos. Path format: <auth.uid()>/<swatch_id>/<file>.jpg
INSERT INTO storage.buckets (id, name, public)
VALUES ('swatch-photos', 'swatch-photos', true)
ON CONFLICT (id) DO UPDATE SET public = EXCLUDED.public;

DROP POLICY IF EXISTS "Swatch photos insert" ON storage.objects;
DROP POLICY IF EXISTS "Swatch photos read" ON storage.objects;
DROP POLICY IF EXISTS "Swatch photos delete" ON storage.objects;

CREATE POLICY "Swatch photos insert"
    ON storage.objects FOR INSERT
    TO authenticated
    WITH CHECK (
        bucket_id = 'swatch-photos'
        AND lower((storage.foldername(name))[1]) = lower(auth.uid()::text)
    );

CREATE POLICY "Swatch photos read"
    ON storage.objects FOR SELECT
    TO public
    USING (bucket_id = 'swatch-photos');

CREATE POLICY "Swatch photos delete"
    ON storage.objects FOR DELETE
    TO authenticated
    USING (
        bucket_id = 'swatch-photos'
        AND lower((storage.foldername(name))[1]) = lower(auth.uid()::text)
    );
