-- Pattern Vault: add structured duration tracking for project notes
-- Run this after 013_app_config.sql

alter table if exists public.project_notes
    add column if not exists duration_minutes integer;

do $$
begin
    if not exists (
        select 1
        from pg_constraint
        where conname = 'project_notes_duration_minutes_nonnegative'
    ) then
        alter table public.project_notes
            add constraint project_notes_duration_minutes_nonnegative
            check (duration_minutes is null or duration_minutes >= 0);
    end if;
end $$;
