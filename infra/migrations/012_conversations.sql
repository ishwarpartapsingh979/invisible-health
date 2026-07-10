-- Every conversation with the coach (all-day, not just workouts) persisted so
-- NOTHING is lost and the coach can recall past chats. Workout sessions still get
-- their own structured row in coaching_sessions; this captures the full to-and-fro
-- of any conversation (food talk, questions, recaps, planning) on session end.
-- Run once in Supabase (project pnbrjxgmaulijamhcyik).

create table if not exists conversations (
    id          uuid primary key default gen_random_uuid(),
    user_id     text not null default 'ishwar',
    started_at  timestamptz not null default now(),
    ended_at    timestamptz not null default now(),
    turns       text,           -- the full "You: ... / Coach: ..." transcript
    summary     text,           -- one-line recap (optional)
    created_at  timestamptz not null default now()
);

create index if not exists idx_conversations_user_date
    on conversations (user_id, started_at desc);
