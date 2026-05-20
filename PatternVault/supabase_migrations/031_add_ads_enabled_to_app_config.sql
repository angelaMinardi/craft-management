-- Corvid Craft Migration 031: Ads remote kill switch
-- Run in Supabase Dashboard → SQL Editor → New query → paste → Run
--
-- Adds ads_enabled to app_config. Flip to false in the Supabase Table Editor
-- to instantly hide all free-tier ads (banner + native card) across all users
-- without an App Store update. Use cases: policy-review pauses, ad-provider
-- incidents, or testing a pure-subscription funnel.

ALTER TABLE public.app_config
    ADD COLUMN IF NOT EXISTS ads_enabled boolean NOT NULL DEFAULT true;

-- Ensure the config row exists (idempotent)
INSERT INTO public.app_config (id, ai_enabled)
VALUES (1, true)
ON CONFLICT (id) DO NOTHING;
