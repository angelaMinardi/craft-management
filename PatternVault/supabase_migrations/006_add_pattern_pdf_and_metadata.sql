-- Pattern Vault Migration 006: Add PDF URL and extended website metadata
-- Run this in Supabase Dashboard -> SQL Editor -> New query -> paste -> Run
--
-- pdf_url: storage URL when user attaches a PDF to the pattern
-- video_url: primary tutorial/walkthrough video URL from pattern page
-- gauge, needle_hook_sizes, yarn_weight_yardage, techniques: structured extract from AI

ALTER TABLE public.patterns
    ADD COLUMN IF NOT EXISTS pdf_url text,
    ADD COLUMN IF NOT EXISTS video_url text,
    ADD COLUMN IF NOT EXISTS gauge text,
    ADD COLUMN IF NOT EXISTS needle_hook_sizes text,
    ADD COLUMN IF NOT EXISTS yarn_weight_yardage text,
    ADD COLUMN IF NOT EXISTS techniques text;
