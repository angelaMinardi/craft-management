-- Pattern Vault Migration 019: Create pattern-images storage bucket + RLS policies
-- The bucket was created via Dashboard but never had RLS policies applied,
-- causing "new row violates row-level security policy" on chart image uploads.
-- Path format: <auth.uid()>/<pattern_id>/<file>.jpg

INSERT INTO storage.buckets (id, name, public)
VALUES ('pattern-images', 'pattern-images', true)
ON CONFLICT (id) DO UPDATE SET public = EXCLUDED.public;

-- Remove any stale policies that may exist from manual attempts
DROP POLICY IF EXISTS "Users can upload pattern images" ON storage.objects;
DROP POLICY IF EXISTS "Public read access for pattern images" ON storage.objects;
DROP POLICY IF EXISTS "Users can delete own pattern images" ON storage.objects;
DROP POLICY IF EXISTS "Pattern images insert" ON storage.objects;
DROP POLICY IF EXISTS "Pattern images read" ON storage.objects;
DROP POLICY IF EXISTS "Pattern images delete" ON storage.objects;

CREATE POLICY "Pattern images insert"
    ON storage.objects FOR INSERT
    TO authenticated
    WITH CHECK (
        bucket_id = 'pattern-images'
        AND lower((storage.foldername(name))[1]) = lower(auth.uid()::text)
    );

CREATE POLICY "Pattern images read"
    ON storage.objects FOR SELECT
    TO public
    USING (bucket_id = 'pattern-images');

CREATE POLICY "Pattern images delete"
    ON storage.objects FOR DELETE
    TO authenticated
    USING (
        bucket_id = 'pattern-images'
        AND lower((storage.foldername(name))[1]) = lower(auth.uid()::text)
    );
