-- Coaching session memory (Tier 3 #8): one row per completed workout so the
-- voice coach REMEMBERS what you did — enabling dad's arc ("yesterday endurance
-- -> today strength"), load management (high RPE yesterday -> lighter today),
-- and "what did I do last?".
--
-- Run once in your Supabase SQL editor. The agent writes here at workout end and
-- reads recent rows at workout start (via the Supabase REST API using
-- SUPABASE_URL + SUPABASE_SERVICE_KEY).

create table if not exists coaching_sessions (
    id            uuid primary key default gen_random_uuid(),
    user_id       text not null default 'ishwar',
    started_at    timestamptz not null default now(),
    ended_at      timestamptz not null default now(),
    duration_min  integer,
    activity_type text,          -- 'strength' | 'endurance' | 'mixed' | 'mobility' | ...
    focus         text,          -- e.g. 'legs', 'upper body', 'run'
    exercises     text,          -- free-text list of what was done
    rpe           integer,       -- 1-10 perceived exertion, if captured
    avg_hr        integer,
    max_hr        integer,
    summary       text,          -- the coach's short recap of the session
    created_at    timestamptz not null default now()
);

create index if not exists idx_coaching_sessions_user_date
    on coaching_sessions (user_id, started_at desc);
