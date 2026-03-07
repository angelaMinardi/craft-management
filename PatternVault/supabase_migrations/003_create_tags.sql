-- Pattern Vault: tags + pattern_tags tables
-- Run this in Supabase Dashboard → SQL Editor → New query → paste → Run

-- Tags table (shared across all users — built-in tags)
create table if not exists public.tags (
    id uuid primary key default gen_random_uuid(),
    name text not null unique,
    category text check (category in ('craft_type', 'difficulty', 'project_type', 'purpose')),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

-- Junction table: many-to-many between patterns and tags
create table if not exists public.pattern_tags (
    pattern_id uuid references public.patterns(id) on delete cascade not null,
    tag_id uuid references public.tags(id) on delete cascade not null,
    primary key (pattern_id, tag_id)
);

-- Indexes
create index if not exists idx_pattern_tags_pattern on public.pattern_tags(pattern_id);
create index if not exists idx_pattern_tags_tag on public.pattern_tags(tag_id);

-- Auto-update updated_at on tags
drop trigger if exists tags_updated_at on public.tags;
create trigger tags_updated_at
    before update on public.tags
    for each row execute function public.set_updated_at();

-- RLS for tags: everyone can read, no one modifies (built-in only)
alter table public.tags enable row level security;

create policy "Anyone can view tags"
    on public.tags for select
    to authenticated
    using (true);

-- RLS for pattern_tags: users can only manage tags on their own patterns
alter table public.pattern_tags enable row level security;

create policy "Users can view tags on their own patterns"
    on public.pattern_tags for select
    to authenticated
    using (
        pattern_id in (
            select id from public.patterns where user_id = auth.uid()
        )
    );

create policy "Users can add tags to their own patterns"
    on public.pattern_tags for insert
    to authenticated
    with check (
        pattern_id in (
            select id from public.patterns where user_id = auth.uid()
        )
    );

create policy "Users can remove tags from their own patterns"
    on public.pattern_tags for delete
    to authenticated
    using (
        pattern_id in (
            select id from public.patterns where user_id = auth.uid()
        )
    );

-- Seed built-in tags
insert into public.tags (name, category) values
    -- Craft type
    ('Crochet', 'craft_type'),
    ('Knitting', 'craft_type'),
    -- Difficulty
    ('Easy', 'difficulty'),
    ('Intermediate', 'difficulty'),
    ('Advanced', 'difficulty'),
    -- Project type
    ('Sweater', 'project_type'),
    ('Hat', 'project_type'),
    ('Scarf', 'project_type'),
    ('Blanket', 'project_type'),
    ('Amigurumi', 'project_type'),
    ('Accessories', 'project_type'),
    ('Home Decor', 'project_type'),
    ('Socks', 'project_type'),
    ('Bag', 'project_type'),
    -- Purpose
    ('Gift Idea', 'purpose'),
    ('Baby', 'purpose'),
    ('Holiday', 'purpose'),
    ('Stash Buster', 'purpose')
on conflict (name) do nothing;
