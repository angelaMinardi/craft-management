-- Corvid Craft Migration 007: Create pattern-pdfs storage bucket
-- Run this in Supabase Dashboard -> SQL Editor -> New query -> paste -> Run
--
-- Bucket for PDF files attached to patterns. Path format: user_id/pattern_id/filename.pdf

INSERT INTO storage.buckets (id, name, public)
VALUES ('pattern-pdfs', 'pattern-pdfs', true)
ON CONFLICT (id) DO NOTHING;

-- RLS: users can upload to their own folder (path starts with their user_id)
CREATE POLICY "Users can upload pattern PDFs"
    ON storage.objects FOR INSERT
    TO authenticated
    WITH CHECK (
        bucket_id = 'pattern-pdfs'
        AND (storage.foldername(name))[1] = auth.uid()::text
    );

CREATE POLICY "Users can view pattern PDFs"
    ON storage.objects FOR SELECT
    TO authenticated
    USING (bucket_id = 'pattern-pdfs');

CREATE POLICY "Users can delete their pattern PDFs"
    ON storage.objects FOR DELETE
    TO authenticated
    USING (
        bucket_id = 'pattern-pdfs'
        AND (storage.foldername(name))[1] = auth.uid()::text
    );
