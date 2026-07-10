-- Voice-logged meals (as-needed, not every meal). The user just SAYS what they
-- ate / are about to eat; the coach assesses it vs the nutrition rules and logs
-- it here for the weekly nutritionist summary. Photo logging comes later.
-- Run once in Supabase (project pnbrjxgmaulijamhcyik).

create table if not exists nutrition_log (
    id          uuid primary key default gen_random_uuid(),
    user_id     text default 'ishwar',
    logged_at   timestamptz not null default now(),
    description text,           -- what they said they ate / considered
    meal        text,           -- breakfast | lunch | dinner | snack
    flags       jsonb,          -- {is_refined, is_fried, contains_sugar, has_protein, ...}
    verdict     text,           -- keep | limit | avoid
    advice      text            -- the coach's short verdict + swap
);

create index if not exists idx_nutrition_log_user_date
    on nutrition_log (user_id, logged_at desc);
