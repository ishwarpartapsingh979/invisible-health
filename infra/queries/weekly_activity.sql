-- WEEKLY AGENT ACTIVITY — the OBJECTIVE half of "how is my agent performing?"
-- (the SUBJECTIVE half = the Langfuse LLM-judge eval, evals/weekly_eval.py).
-- Run these in Supabase any time to see what the brain actually did this week.

-- 1) Headline counts, last 7 days.
select 'sessions coached'         as metric, count(*)::text as value from coaching_sessions where started_at > now() - interval '7 days'
union all select 'rules fired (total)',       count(*)::text from rule_firings     where fired_at   > now() - interval '7 days'
union all select 'meals logged',              count(*)::text from nutrition_log    where logged_at  > now() - interval '7 days'
union all select 'facts learned about you',   count(*)::text from user_facts       where created_at > now() - interval '7 days'
union all select 'plans decided',             count(*)::text from planned_workouts where created_at > now() - interval '7 days';

-- 2) Rules fired by domain — is the brain actually driving training + nutrition?
select domain, count(*) as fired
from rule_firings
where fired_at > now() - interval '7 days'
group by domain order by fired desc;

-- 3) The flywheel filling up — what it has learned about you, by category.
select category, count(*) as facts
from user_facts
where status = 'active'
group by category order by facts desc;

-- 4) Read the actual meals it logged + its verdicts this week.
select logged_at, description, verdict, advice
from nutrition_log
where logged_at > now() - interval '7 days'
order by logged_at desc;

-- 5) Read exactly what it learned about you this week (spot-check the flywheel).
select created_at, category, fact, confidence
from user_facts
where created_at > now() - interval '7 days'
order by created_at desc;
