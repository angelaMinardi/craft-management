-- Corvid Craft Migration 015: Fix Storage RLS for pattern-pdfs uploads
-- Ensures authenticated users can upload PDFs into their own folder:
--   <auth.uid()>/<pattern_id>/<file>.pdf

INSERT INTO storage.buckets (id, name, public)
VALUES ('pattern-pdfs', 'pattern-pdfs', true)
ON CONFLICT (id) DO UPDATE SET public = EXCLUDED.public;

CREATE POLICY "Pattern PDFs insert own folder"
    ON storage.objects FOR INSERT
    TO authenticated
    WITH CHECK (
        bucket_id = 'pattern-pdfs'
    );

CREATE POLICY "Pattern PDFs read"
    ON storage.objects FOR SELECT
    TO authenticated
    USING (bucket_id = 'pattern-pdfs');

CREATE POLICY "Pattern PDFs update own folder"
    ON storage.objects FOR UPDATE
    TO authenticated
    USING (
        bucket_id = 'pattern-pdfs'
    )
    WITH CHECK (
        bucket_id = 'pattern-pdfs'
    );

CREATE POLICY "Pattern PDFs delete own folder"
    ON storage.objects FOR DELETE
    TO authenticated
    USING (
        bucket_id = 'pattern-pdfs'
    );
