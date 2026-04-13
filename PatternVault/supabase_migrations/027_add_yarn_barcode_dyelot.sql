-- Add barcode, dye_lot, and fiber_content to yarn_stash
-- Run this in Supabase Dashboard → SQL Editor → New query → paste → Run

ALTER TABLE public.yarn_stash ADD COLUMN IF NOT EXISTS barcode text;
ALTER TABLE public.yarn_stash ADD COLUMN IF NOT EXISTS dye_lot text;
ALTER TABLE public.yarn_stash ADD COLUMN IF NOT EXISTS fiber_content text;
