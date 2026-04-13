-- 020: Create waitlist_signups table for pre-launch email collection
-- Accessed only by the waitlist-signup edge function (service role).

CREATE TABLE IF NOT EXISTS public.waitlist_signups (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email text NOT NULL UNIQUE,
  archetype text,
  referral_source text,
  signed_up_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.waitlist_signups ENABLE ROW LEVEL SECURITY;

-- No RLS policies = only service_role can read/write (edge function).
-- No client-side access needed.

CREATE INDEX idx_waitlist_signups_email ON public.waitlist_signups (email);
