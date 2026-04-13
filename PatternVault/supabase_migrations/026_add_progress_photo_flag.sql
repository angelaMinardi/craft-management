-- Add is_progress_photo flag to pattern_images for progress photo gallery
-- Run this in Supabase Dashboard → SQL Editor → New query → paste → Run

ALTER TABLE public.pattern_images ADD COLUMN IF NOT EXISTS is_progress_photo boolean DEFAULT false;
