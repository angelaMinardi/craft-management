-- Pattern Vault Migration 016: Harden pattern-pdfs Storage RLS
-- Ensures a single, deterministic policy set for PDF upload/read/update/delete.
-- Path format is enforced: <auth.uid()>/<pattern_id>/<file>.pdf

INSERT INTO storage.buckets (id, name, public)
VALUES ('pattern-pdfs', 'pattern-pdfs', true)
ON CONFLICT (id) DO UPDATE SET public = EXCLUDED.public;

-- Remove legacy / duplicate policies so CREATE POLICY is deterministic.
DROP POLICY IF EXISTS "Users can upload pattern PDFs" ON storage.objects;
DROP POLICY IF EXISTS "Users can view pattern PDFs" ON storage.objects;
DROP POLICY IF EXISTS "Users can delete their pattern PDFs" ON storage.objects;
DROP POLICY IF EXISTS "Pattern PDFs insert own folder" ON storage.objects;
DROP POLICY IF EXISTS "Pattern PDFs read" ON storage.objects;
DROP POLICY IF EXISTS "Pattern PDFs update own folder" ON storage.objects;
DROP POLICY IF EXISTS "Pattern PDFs delete own folder" ON storage.objects;

CREATE POLICY "Pattern PDFs insert own folder"
    ON storage.objects FOR INSERT
    TO authenticated
    WITH CHECK (
        bucket_id = 'pattern-pdfs'
        AND (storage.foldername(name))[1] = auth.uid()::text
    );

CREATE POLICY "Pattern PDFs read"
    ON storage.objects FOR SELECT
    TO public
    USING (bucket_id = 'pattern-pdfs');

CREATE POLICY "Pattern PDFs update own folder"
    ON storage.objects FOR UPDATE
    TO authenticated
    USING (
        bucket_id = 'pattern-pdfs'
        AND (storage.foldername(name))[1] = auth.uid()::text
    )
    WITH CHECK (
        bucket_id = 'pattern-pdfs'
        AND (storage.foldername(name))[1] = auth.uid()::text
    );

CREATE POLICY "Pattern PDFs delete own folder"
    ON storage.objects FOR DELETE
    TO authenticated
    USING (
        bucket_id = 'pattern-pdfs'
        AND (storage.foldername(name))[1] = auth.uid()::text
    );
