-- 022: Add beta application fields to waitlist_signups
-- Collects more info to help select and onboard beta testers.

ALTER TABLE public.waitlist_signups
  ADD COLUMN IF NOT EXISTS name text,
  ADD COLUMN IF NOT EXISTS craft_types text[] DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS current_method text,
  ADD COLUMN IF NOT EXISTS device text;
