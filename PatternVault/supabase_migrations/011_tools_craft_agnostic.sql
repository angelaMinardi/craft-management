-- Pattern Vault Migration 011: Tools craft-agnostic
-- Run in Supabase Dashboard → SQL Editor after 010.
-- Allows any tool type (e.g. needle, hook, leather cutter) instead of only needle/hook.

-- Drop the CHECK that restricts type to 'needle' or 'hook'.
-- PostgreSQL names inline CHECK constraints as: tablename_columnname_check
ALTER TABLE public.needle_hook_inventory
    DROP CONSTRAINT IF EXISTS needle_hook_inventory_type_check;
