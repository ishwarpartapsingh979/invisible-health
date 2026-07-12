-- #12: persist the calories/macros the agent can now estimate (via lookup_product
-- or clear knowledge). nutrition_log previously had no numeric columns.
alter table nutrition_log add column if not exists calories  numeric;
alter table nutrition_log add column if not exists protein_g numeric;
alter table nutrition_log add column if not exists carbs_g   numeric;
alter table nutrition_log add column if not exists fat_g     numeric;

-- #21: when the coach answers WITHOUT a backing rule (its own knowledge), log the
-- question here so it can be taken to the nutritionist / dad to create a real rule.
create table if not exists rule_gaps (
    id          uuid primary key default gen_random_uuid(),
    user_id     text default 'ishwar',
    domain      text,          -- nutrition | coach | sports_science | general
    question    text,          -- what the user asked that no rule covered
    coach_answer text,         -- what the coach answered from its own knowledge
    local_date  date,
    created_at  timestamptz not null default now()
);
create index if not exists idx_rule_gaps_user on rule_gaps (user_id, created_at desc);
