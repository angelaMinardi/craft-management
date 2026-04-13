-- Add collection_id FK to patterns for folder assignment
-- Run this in Supabase Dashboard → SQL Editor → New query → paste → Run

ALTER TABLE public.patterns
    ADD COLUMN collection_id uuid REFERENCES public.collections(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_patterns_collection ON public.patterns(user_id, collection_id);
