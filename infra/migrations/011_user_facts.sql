-- The PERSONALIZATION FLYWHEEL: durable things the coach learns about the user as
-- they talk, so every future conversation feels more "them". The coach writes here
-- via the remember_about_user tool (reactively, woven into normal replies); the
-- agent loads these back into its context at the start of every session.
-- Run once in Supabase (project pnbrjxgmaulijamhcyik).

create table if not exists user_facts (
    id          uuid primary key default gen_random_uuid(),
    user_id     text default 'ishwar',
    category    text,           -- preference | constraint | motivation | body_response | context | food | adherence | mood
    fact        text not null,  -- short, third-person: "hates burpees", "left knee flares on deep squats"
    confidence  text default 'medium',   -- low | medium | high
    source      text default 'conversation',
    status      text default 'active',   -- active | stale
    created_at  timestamptz not null default now(),
    updated_at  timestamptz not null default now()
);

create index if not exists idx_user_facts_user
    on user_facts (user_id, status, updated_at desc);
