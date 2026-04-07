-- 009: Add parsed_steps column for AI-extracted step data
-- Stores JSON array: [{"title": "Cast On", "body": "CO 120 sts..."}, ...]
-- Safe to run again if column already exists.
ALTER TABLE patterns ADD COLUMN IF NOT EXISTS parsed_steps TEXT;
