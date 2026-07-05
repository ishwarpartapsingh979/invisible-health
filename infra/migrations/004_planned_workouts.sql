-- Full plan lifecycle memory (Tier 3 redesign): store what the coach SUGGESTED,
-- the DISCUSSION, and what the user DECIDED — separate from what they actually
-- DID (coaching_sessions). Run once in Supabase (project pnbrjxgmaulijamhcyik).

create table if not exists planned_workouts (
    id          uuid primary key default gen_random_uuid(),
    user_id     text not null default 'ishwar',
    decided     text,          -- the workout the user chose
    suggested   text,          -- JSON of the 3 plans the coach proposed
    discussion  text,          -- the full to-and-fro of the planning chat
    status      text default 'planned',   -- planned | done | skipped
    created_at  timestamptz not null default now()
);

create index if not exists idx_planned_workouts_user_date
    on planned_workouts (user_id, created_at desc);

-- Link the actual session to what was planned.
alter table coaching_sessions add column if not exists decided text;
