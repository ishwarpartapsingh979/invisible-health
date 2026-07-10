-- Phase 3 readiness: map the live WHOOP recovery score into training guidance.
-- The agent (_whoop_facts) sets recovery_band using WHOOP's OWN official ranges
-- (red 0-33, yellow 34-66, green 67-100) — those bands are NOT invented. The
-- training RESPONSE below is deliberately CONSERVATIVE and follows WHOOP's own
-- "prioritise recovery on red" guidance. The exact dosing (how much to pull back,
-- what counts as green-light) is FLAGGED for the sports-science (Seerat) review —
-- see memory. Subjective self-report still overrides this: in the agent the
-- coach-passed keys merge AFTER these, so "I feel wrecked" beats a green score.
-- source=sports_science. Run AFTER 006. Reseed just these three:
delete from rules where source like 'whoop-recovery:%';

insert into rules (domain, trigger_conditions, action_forces, action_vetoes, rationale, tier, source)
values ('sports_science', '{"recovery_band": "red"}'::jsonb,
        '["prioritise recovery today — easy movement, mobility or a light aerobic session only; keep it well short of failure"]'::jsonb,
        '["max-effort work", "chasing a PR or a new heavy top set today"]'::jsonb,
        'WHOOP red recovery (<34%): the body is under strain — WHOOP''s own guidance is to prioritise recovery. Go light. (Exact dosing pending Seerat.)',
        1, 'whoop-recovery:red');

insert into rules (domain, trigger_conditions, action_forces, action_vetoes, rationale, tier, source)
values ('sports_science', '{"recovery_band": "yellow"}'::jsonb,
        '["moderate day — train, but keep it controlled and leave 1-2 reps in reserve; don''t hunt a PR"]'::jsonb,
        '[]'::jsonb,
        'WHOOP yellow recovery (34-66%): fine to train, but hold something back rather than maxing out. (Exact dosing pending Seerat.)',
        2, 'whoop-recovery:yellow');

insert into rules (domain, trigger_conditions, action_forces, action_vetoes, rationale, tier, source)
values ('sports_science', '{"recovery_band": "green"}'::jsonb,
        '["cleared for harder work IF you feel it — but green is not a mandate to max out; let how you actually feel (RPE/talk-test) set the ceiling"]'::jsonb,
        '[]'::jsonb,
        'WHOOP green recovery (>=67%): capacity is there, but a good score is not a green light to max out — feel leads. (Confirm with Seerat.)',
        3, 'whoop-recovery:green');
