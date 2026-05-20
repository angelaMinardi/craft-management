-- Corvid Craft Migration 029: Launch-only lifetime offer plumbing
-- Run in Supabase Dashboard → SQL Editor → New query → paste → Run
--
-- Adds lifetime-offer control fields to app_config + a record_lifetime_purchase() RPC.
-- The lifetime SKU is available from May 1, 2026 → Nov 1, 2026 OR until 1,000 buyers, whichever comes first.
-- Kill-switch behavior mirrors the existing ai_enabled flag.

-- 1. Extend app_config with lifetime-offer fields
ALTER TABLE public.app_config
    ADD COLUMN IF NOT EXISTS lifetime_offer_enabled boolean NOT NULL DEFAULT true,
    ADD COLUMN IF NOT EXISTS lifetime_buyer_count integer NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS lifetime_buyer_cap integer NOT NULL DEFAULT 1000,
    ADD COLUMN IF NOT EXISTS lifetime_offer_ends_at timestamptz NOT NULL DEFAULT '2026-11-01 00:00:00-07'::timestamptz,
    ADD COLUMN IF NOT EXISTS lifetime_offer_starts_at timestamptz NOT NULL DEFAULT '2026-05-01 00:00:00-07'::timestamptz;

-- Make sure the single config row exists (idempotent)
INSERT INTO public.app_config (id, ai_enabled)
VALUES (1, true)
ON CONFLICT (id) DO NOTHING;

-- 2. RPC: record_lifetime_purchase
-- Called by the client after StoreKit verifies a lifetime purchase.
-- Atomically increments the buyer count and auto-disables the offer
-- when the cap is reached. Returns the new state so the client can
-- refresh its cache without another round-trip.
CREATE OR REPLACE FUNCTION public.record_lifetime_purchase()
RETURNS TABLE (
    buyer_count integer,
    offer_enabled boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_count integer;
    v_cap integer;
    v_enabled boolean;
BEGIN
    -- Lock the row for update to avoid races between concurrent purchases
    SELECT lifetime_buyer_count, lifetime_buyer_cap, lifetime_offer_enabled
    INTO v_count, v_cap, v_enabled
    FROM public.app_config
    WHERE id = 1
    FOR UPDATE;

    v_count := v_count + 1;

    -- Trip the kill-switch when we hit the cap
    IF v_count >= v_cap THEN
        v_enabled := false;
    END IF;

    UPDATE public.app_config
    SET lifetime_buyer_count = v_count,
        lifetime_offer_enabled = v_enabled,
        updated_at = now()
    WHERE id = 1;

    RETURN QUERY SELECT v_count, v_enabled;
END;
$$;

GRANT EXECUTE ON FUNCTION public.record_lifetime_purchase() TO authenticated;

-- 3. RPC: expire_lifetime_offer_if_past_end_date
-- Called on each remote-config fetch from the client. Cheap idempotent safety net so
-- the offer auto-expires on Nov 1 even if no cron is configured.
CREATE OR REPLACE FUNCTION public.expire_lifetime_offer_if_past_end_date()
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_ends timestamptz;
    v_enabled boolean;
BEGIN
    SELECT lifetime_offer_ends_at, lifetime_offer_enabled
    INTO v_ends, v_enabled
    FROM public.app_config
    WHERE id = 1;

    IF v_enabled AND now() >= v_ends THEN
        UPDATE public.app_config
        SET lifetime_offer_enabled = false,
            updated_at = now()
        WHERE id = 1;
        RETURN false;
    END IF;
    RETURN v_enabled;
END;
$$;

GRANT EXECUTE ON FUNCTION public.expire_lifetime_offer_if_past_end_date() TO anon;
GRANT EXECUTE ON FUNCTION public.expire_lifetime_offer_if_past_end_date() TO authenticated;
