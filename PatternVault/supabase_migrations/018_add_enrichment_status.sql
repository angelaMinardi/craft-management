-- 018: Add enrichment status tracking for async AI processing
-- New patterns from share extension save quickly with enrichment_status='pending',
-- then a server-side Edge Function runs AI analysis and updates to 'complete'/'failed'.
-- Existing patterns default to 'complete' (already have their data).
ALTER TABLE patterns ADD COLUMN IF NOT EXISTS enrichment_status TEXT DEFAULT 'complete';
ALTER TABLE patterns ADD COLUMN IF NOT EXISTS enrichment_error TEXT;
ALTER TABLE patterns ADD COLUMN IF NOT EXISTS enrichment_started_at TIMESTAMPTZ;
ALTER TABLE patterns ADD COLUMN IF NOT EXISTS enrichment_completed_at TIMESTAMPTZ;
