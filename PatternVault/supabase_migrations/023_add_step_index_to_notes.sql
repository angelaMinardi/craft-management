-- Add step_index to project_notes for per-step note association
-- Run this in Supabase Dashboard → SQL Editor → New query → paste → Run

ALTER TABLE public.project_notes ADD COLUMN step_index int;
