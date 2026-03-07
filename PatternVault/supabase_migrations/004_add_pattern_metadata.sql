-- Pattern Vault Migration 004: Add pattern metadata columns
-- Run this in Supabase Dashboard -> SQL Editor -> New query -> paste -> Run
--
-- These columns store AI-extracted metadata from the share extension:
--   difficulty  — beginner/intermediate/advanced/expert
--   materials   — free-text summary of required materials
--   craft_type  — knitting/crochet/sewing/etc
--   source_content — extracted page text for in-app viewing

ALTER TABLE public.patterns
    ADD COLUMN IF NOT EXISTS difficulty text,
    ADD COLUMN IF NOT EXISTS materials text,
    ADD COLUMN IF NOT EXISTS craft_type text,
    ADD COLUMN IF NOT EXISTS source_content text;
