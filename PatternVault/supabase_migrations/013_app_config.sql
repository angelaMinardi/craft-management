-- Pattern Vault Migration 013: App config (AI kill switch)
-- Run in Supabase Dashboard → SQL Editor → New query → paste → Run
--
-- Single-row table for app-wide settings. Used to disable AI (Share Extension + main app)
-- when you hit your monthly cost cap. Flip ai_enabled to false in Table Editor to turn off AI.

CREATE TABLE IF NOT EXISTS public.app_config (
    id integer PRIMARY KEY DEFAULT 1,
    ai_enabled boolean NOT NULL DEFAULT true,
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT app_config_single_row CHECK (id = 1)
);

-- Ensure exactly one row
INSERT INTO public.app_config (id, ai_enabled)
VALUES (1, true)
ON CONFLICT (id) DO NOTHING;

ALTER TABLE public.app_config ENABLE ROW LEVEL SECURITY;

-- Anyone (anon + authenticated) can read; only service role / dashboard can update
CREATE POLICY "Allow read app_config"
    ON public.app_config FOR SELECT
    USING (true);

-- No UPDATE/INSERT policy for anon or authenticated: use Supabase Dashboard → Table Editor
-- to set ai_enabled = false when you need to hit the kill switch.

GRANT SELECT ON public.app_config TO anon;
GRANT SELECT ON public.app_config TO authenticated;
