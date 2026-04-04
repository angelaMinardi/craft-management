-- 014_add_parsed_rows.sql
-- Add parsed_rows column for AI-extracted row-level pattern instructions.
-- Stores JSON: [{"id":1,"instruction":"K2, P2...","stitchCount":40,...}]

ALTER TABLE patterns ADD COLUMN parsed_rows TEXT;
