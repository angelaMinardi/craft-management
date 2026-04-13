-- Add 'frogged' as a valid pattern status
-- Run this in Supabase Dashboard → SQL Editor → New query → paste → Run

-- Drop the existing CHECK constraint and re-create with 'frogged' included
alter table public.patterns
    drop constraint if exists patterns_status_check;

alter table public.patterns
    add constraint patterns_status_check
    check (status in ('want_to_make', 'in_progress', 'completed', 'frogged'));
