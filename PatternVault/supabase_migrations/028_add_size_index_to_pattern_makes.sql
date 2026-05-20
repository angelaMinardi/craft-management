-- Add size_index to pattern_makes for linking to multi-size repeat instructions.
-- 0-based index into targetStitchCounts arrays (0=smallest size).

ALTER TABLE pattern_makes
ADD COLUMN IF NOT EXISTS size_index INTEGER;
