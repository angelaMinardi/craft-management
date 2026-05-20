-- Corvid Craft: patterns table
-- Run this in Supabase Dashboard → SQL Editor → New query → paste → Run

create table if not exists public.patterns (
    id uuid primary key default gen_random_uuid(),
    user_id uuid references auth.users(id) on delete cascade not null,
    title text not null,
    description text,
    source_url text not null,
    source_platform text,
    status text not null default 'want_to_make'
        check (status in ('want_to_make', 'in_progress', 'completed')),
    thumbnail_url text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

-- Index for fast user lookups
create index if not exists idx_patterns_user_id on public.patterns(user_id);
create index if not exists idx_patterns_status on public.patterns(user_id, status);

-- Auto-update updated_at on row changes
create or replace function public.set_updated_at()
returns trigger as $$
begin
    new.updated_at = now();
    return new;
end;
$$ language plpgsql;

drop trigger if exists patterns_updated_at on public.patterns;
create trigger patterns_updated_at
    before update on public.patterns
    for each row execute function public.set_updated_at();

-- Row Level Security: users can only access their own patterns
alter table public.patterns enable row level security;

create policy "Users can view their own patterns"
    on public.patterns for select
    using (auth.uid() = user_id);

create policy "Users can insert their own patterns"
    on public.patterns for insert
    with check (auth.uid() = user_id);

create policy "Users can update their own patterns"
    on public.patterns for update
    using (auth.uid() = user_id);

create policy "Users can delete their own patterns"
    on public.patterns for delete
    using (auth.uid() = user_id);
