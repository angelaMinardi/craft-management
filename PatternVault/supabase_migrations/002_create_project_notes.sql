-- Corvid Craft: project_notes table
-- Run this in Supabase Dashboard → SQL Editor → New query → paste → Run

create table if not exists public.project_notes (
    id uuid primary key default gen_random_uuid(),
    pattern_id uuid references public.patterns(id) on delete cascade not null,
    user_id uuid references auth.users(id) on delete cascade not null,
    note_type text not null
        check (note_type in ('general', 'yarn_info', 'modifications', 'progress_update')),
    content text not null,
    photo_url text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

-- Indexes
create index if not exists idx_project_notes_pattern on public.project_notes(pattern_id);
create index if not exists idx_project_notes_user on public.project_notes(user_id);

-- Auto-update updated_at on row changes (reuses set_updated_at() from 001)
drop trigger if exists project_notes_updated_at on public.project_notes;
create trigger project_notes_updated_at
    before update on public.project_notes
    for each row execute function public.set_updated_at();

-- Row Level Security: users can only access their own notes
alter table public.project_notes enable row level security;

create policy "Users can view their own notes"
    on public.project_notes for select
    using (auth.uid() = user_id);

create policy "Users can insert their own notes"
    on public.project_notes for insert
    with check (auth.uid() = user_id);

create policy "Users can update their own notes"
    on public.project_notes for update
    using (auth.uid() = user_id);

create policy "Users can delete their own notes"
    on public.project_notes for delete
    using (auth.uid() = user_id);
