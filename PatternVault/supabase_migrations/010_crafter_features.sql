-- Pattern Vault Migration 010: Crafter features
-- Run in Supabase Dashboard → SQL Editor → New query → paste → Run
--
-- Tables: yarn_stash, needle_hook_inventory, pattern_makes, pattern_reminders

-- 1. Yarn stash: user's yarn inventory
CREATE TABLE IF NOT EXISTS public.yarn_stash (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    brand_name text NOT NULL,
    color_name text,
    weight text,
    yardage_per_skein integer,
    skeins_owned real NOT NULL DEFAULT 1,
    location text,
    notes text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_yarn_stash_user ON public.yarn_stash(user_id);

DROP TRIGGER IF EXISTS yarn_stash_updated_at ON public.yarn_stash;
CREATE TRIGGER yarn_stash_updated_at
    BEFORE UPDATE ON public.yarn_stash
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.yarn_stash ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own yarn stash"
    ON public.yarn_stash FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can insert their own yarn stash"
    ON public.yarn_stash FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can update their own yarn stash"
    ON public.yarn_stash FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "Users can delete their own yarn stash"
    ON public.yarn_stash FOR DELETE USING (auth.uid() = user_id);

-- 2. Needle/hook inventory
CREATE TABLE IF NOT EXISTS public.needle_hook_inventory (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    type text NOT NULL CHECK (type IN ('needle', 'hook')),
    size text NOT NULL,
    length_cm real,
    notes text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_needle_hook_user ON public.needle_hook_inventory(user_id);
CREATE INDEX IF NOT EXISTS idx_needle_hook_type ON public.needle_hook_inventory(user_id, type);

DROP TRIGGER IF EXISTS needle_hook_inventory_updated_at ON public.needle_hook_inventory;
CREATE TRIGGER needle_hook_inventory_updated_at
    BEFORE UPDATE ON public.needle_hook_inventory
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.needle_hook_inventory ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own needle hook inventory"
    ON public.needle_hook_inventory FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can insert their own needle hook inventory"
    ON public.needle_hook_inventory FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can update their own needle hook inventory"
    ON public.needle_hook_inventory FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "Users can delete their own needle hook inventory"
    ON public.needle_hook_inventory FOR DELETE USING (auth.uid() = user_id);

-- 3. Pattern makes: multiple projects per pattern (e.g. Make 1, Make 2, "Gift for Mom")
CREATE TABLE IF NOT EXISTS public.pattern_makes (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    pattern_id uuid REFERENCES public.patterns(id) ON DELETE CASCADE NOT NULL,
    user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    name text NOT NULL DEFAULT 'Make 1',
    size_name text,
    yardage_used integer,
    size_measurements text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_pattern_makes_pattern ON public.pattern_makes(pattern_id);
CREATE INDEX IF NOT EXISTS idx_pattern_makes_user ON public.pattern_makes(user_id);

DROP TRIGGER IF EXISTS pattern_makes_updated_at ON public.pattern_makes;
CREATE TRIGGER pattern_makes_updated_at
    BEFORE UPDATE ON public.pattern_makes
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.pattern_makes ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own pattern makes"
    ON public.pattern_makes FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can insert their own pattern makes"
    ON public.pattern_makes FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can update their own pattern makes"
    ON public.pattern_makes FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "Users can delete their own pattern makes"
    ON public.pattern_makes FOR DELETE USING (auth.uid() = user_id);

-- 4. Reminders / focus list: remind_at = when to notify; sort_order = focus list order
CREATE TABLE IF NOT EXISTS public.pattern_reminders (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    pattern_id uuid REFERENCES public.patterns(id) ON DELETE CASCADE NOT NULL,
    remind_at timestamptz,
    sort_order integer NOT NULL DEFAULT 0,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE(user_id, pattern_id)
);

CREATE INDEX IF NOT EXISTS idx_pattern_reminders_user ON public.pattern_reminders(user_id);
CREATE INDEX IF NOT EXISTS idx_pattern_reminders_remind_at ON public.pattern_reminders(remind_at) WHERE remind_at IS NOT NULL;

DROP TRIGGER IF EXISTS pattern_reminders_updated_at ON public.pattern_reminders;
CREATE TRIGGER pattern_reminders_updated_at
    BEFORE UPDATE ON public.pattern_reminders
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.pattern_reminders ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own pattern reminders"
    ON public.pattern_reminders FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can insert their own pattern reminders"
    ON public.pattern_reminders FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can update their own pattern reminders"
    ON public.pattern_reminders FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "Users can delete their own pattern reminders"
    ON public.pattern_reminders FOR DELETE USING (auth.uid() = user_id);
