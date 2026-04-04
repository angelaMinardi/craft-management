-- Pattern Vault Migration 017: Make pattern-pdfs RLS UID check case-insensitive
-- Swift UUID().uuidString can produce uppercase letters, while auth.uid()::text is often lowercase.
-- Compare lowercase text to avoid false RLS failures on storage uploads.

DROP POLICY IF EXISTS "Pattern PDFs insert own folder" ON storage.objects;
DROP POLICY IF EXISTS "Pattern PDFs update own folder" ON storage.objects;
DROP POLICY IF EXISTS "Pattern PDFs delete own folder" ON storage.objects;

CREATE POLICY "Pattern PDFs insert own folder"
    ON storage.objects FOR INSERT
    TO authenticated
    WITH CHECK (
        bucket_id = 'pattern-pdfs'
        AND lower((storage.foldername(name))[1]) = lower(auth.uid()::text)
    );

CREATE POLICY "Pattern PDFs update own folder"
    ON storage.objects FOR UPDATE
    TO authenticated
    USING (
        bucket_id = 'pattern-pdfs'
        AND lower((storage.foldername(name))[1]) = lower(auth.uid()::text)
    )
    WITH CHECK (
        bucket_id = 'pattern-pdfs'
        AND lower((storage.foldername(name))[1]) = lower(auth.uid()::text)
    );

CREATE POLICY "Pattern PDFs delete own folder"
    ON storage.objects FOR DELETE
    TO authenticated
    USING (
        bucket_id = 'pattern-pdfs'
        AND lower((storage.foldername(name))[1]) = lower(auth.uid()::text)
    );
