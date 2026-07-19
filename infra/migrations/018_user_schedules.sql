-- "Show Me": schedules the user feeds the AI via screenshot / screen-recording /
-- upload (login-gated class timetables, society fitness classes, nutrition/diet
-- charts). Gemini extracts them; stored per user WITH a validity window because
-- schedules are week-specific — the coach uses whichever covers "now" and asks for
-- a fresh capture once it expires. Run once in Supabase.

create table if not exists user_schedules (
    id          uuid primary key default gen_random_uuid(),
    user_id     text default 'ishwar',
    kind        text,          -- fitness | nutrition | other
    title       text,          -- e.g. "Cult Shantiniketan", "Society yoga"
    source      text,          -- screenshot | recording | upload
    extracted   jsonb,         -- structured slots / diet chart
    raw_text    text,          -- the model's plain-text read (fallback)
    captured_at timestamptz not null default now(),
    valid_from  date,          -- the week/period this schedule covers
    valid_to    date,
    created_at  timestamptz not null default now()
);

create index if not exists idx_user_schedules_user
    on user_schedules (user_id, valid_to desc);
