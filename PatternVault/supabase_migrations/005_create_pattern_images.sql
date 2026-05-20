-- Corvid Craft Migration 005: Create pattern_images table
-- Run this in Supabase Dashboard -> SQL Editor -> New query -> paste -> Run
--
-- ALSO: Create storage bucket 'pattern-images' in Supabase Dashboard -> Storage
-- Settings: Public bucket = true (same as note-photos)

CREATE TABLE IF NOT EXISTS public.pattern_images (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    pattern_id uuid REFERENCES public.patterns(id) ON DELETE CASCADE NOT NULL,
    user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    image_url text NOT NULL,
    display_order integer NOT NULL DEFAULT 0,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_pattern_images_pattern ON public.pattern_images(pattern_id);
CREATE INDEX IF NOT EXISTS idx_pattern_images_user ON public.pattern_images(user_id);

ALTER TABLE public.pattern_images ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own pattern images"
    ON public.pattern_images FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own pattern images"
    ON public.pattern_images FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete their own pattern images"
    ON public.pattern_images FOR DELETE
    USING (auth.uid() = user_id);

-- Storage bucket policies (run if bucket was created via Dashboard):
-- INSERT INTO storage.buckets (id, name, public) VALUES ('pattern-images', 'pattern-images', true);
-- CREATE POLICY "Users can upload pattern images" ON storage.objects
--   FOR INSERT TO authenticated WITH CHECK (bucket_id = 'pattern-images');
-- CREATE POLICY "Public read access for pattern images" ON storage.objects
--   FOR SELECT TO public USING (bucket_id = 'pattern-images');
-- CREATE POLICY "Users can delete own pattern images" ON storage.objects
--   FOR DELETE TO authenticated USING (bucket_id = 'pattern-images');
