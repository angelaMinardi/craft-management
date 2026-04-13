-- 021: Create mascot naming poll votes table
-- Stores anonymous votes for the mascot naming poll.

CREATE TABLE IF NOT EXISTS public.mascot_poll_votes (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  name_choice text NOT NULL,
  voter_id text NOT NULL,
  voted_at timestamptz DEFAULT now() NOT NULL
);

ALTER TABLE public.mascot_poll_votes ENABLE ROW LEVEL SECURITY;

-- No RLS policies — service_role only (edge function access)
-- Unique constraint on voter_id to prevent double-voting
CREATE UNIQUE INDEX IF NOT EXISTS idx_mascot_poll_voter ON public.mascot_poll_votes(voter_id);
