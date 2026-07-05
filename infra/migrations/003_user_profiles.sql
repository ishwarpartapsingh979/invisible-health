-- User profile (Tier 3 #11): captured by voice onboarding (or the text form),
-- so the coach knows the user's goal/preferences and can generate today's plans.
-- Run once in your Supabase SQL editor (project pnbrjxgmaulijamhcyik).

create table if not exists user_profiles (
    user_id       text primary key default 'ishwar',
    goal          text,
    preferred     text,
    level         text,
    days_per_week integer,
    equipment     text,
    injuries      text,
    notes         text,          -- the extra thing the coach asked at the end
    updated_at    timestamptz not null default now()
);
