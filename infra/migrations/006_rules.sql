-- Unified RULES layer (Phase 1: decouple decisions from the LLM). One table,
-- domain-tagged, so coach + sports-science + nutrition rules share one engine and
-- can be cross-domain. Reuses the dad-OS trigger->forces/vetoes format. Run once
-- in Supabase (project pnbrjxgmaulijamhcyik).

create table if not exists rules (
    id                 uuid primary key default gen_random_uuid(),
    domain             text not null default 'coach',   -- coach | sports_science | nutrition
    trigger_conditions jsonb not null default '{}'::jsonb,
    action_forces      jsonb not null default '[]'::jsonb,
    action_vetoes      jsonb not null default '[]'::jsonb,
    rationale          text,
    tier               int  not null default 1,  -- 0 safety, 1 arc, 2 sizing, 3 preference
    source             text,                     -- provenance back to rules-source/
    priority           int  default 0,
    status             text default 'active',
    created_at         timestamptz not null default now()
);
create index if not exists idx_rules_domain on rules (domain, status, tier);

-- Every rule firing logged -> auditable + becomes ML training data later.
create table if not exists rule_firings (
    id        uuid primary key default gen_random_uuid(),
    user_id   text default 'ishwar',
    rule_id   uuid,
    domain    text,
    decision  jsonb,     -- the resolved {do,dont,because}
    context   jsonb,     -- the fused context at firing time
    fired_at  timestamptz not null default now()
);

-- Seed: dad's 15 rules from rules-source/dad_os_rules.csv (verbatim).

insert into rules (id, domain, trigger_conditions, action_forces, action_vetoes, rationale, tier, source)
values ('0d918c5d-fe41-46b3-93f0-bb6574bff640', 'coach', '{"exercise_type": "upper abs"}'::jsonb, '["use medicine ball 2-5kg", "keep lower back on the ground"]'::jsonb, '["weighted exercise > 5kg"]'::jsonb, 'Using heavy weights for upper abs is extremely prone to causing injury. A lighter medicine ball with proper form, ensuring the lower back stays on the ground, is a safer and more effective alternative.', 0, 'dad_csv:row1') on conflict (id) do nothing;
insert into rules (id, domain, trigger_conditions, action_forces, action_vetoes, rationale, tier, source)
values ('140d6fc6-1ed6-4fb0-a765-788a6ba7ac78', 'coach', '{"current_day_focus": "upper_body", "previous_day_activity": "strides"}'::jsonb, '["bodyweight squats", "minimal leg exercises"]'::jsonb, '["weighted leg exercises", "high-intensity leg exercises"]'::jsonb, 'Strides are taxing on the legs. The following day''s leg work should be minimal to prioritize recovery, even when the main workout targets the upper body.', 1, 'dad_csv:row2') on conflict (id) do nothing;
insert into rules (id, domain, trigger_conditions, action_forces, action_vetoes, rationale, tier, source)
values ('28cd8886-af83-4957-9f32-5d4678928115', 'coach', '{"physical_state": "tired after recent strides", "recent_activity": "strides", "days_since_activity": "2-3"}'::jsonb, '["repeat previous stride workout"]'::jsonb, '["increase stride count", "increase stride effort"]'::jsonb, 'If the body feels tired days after a specific workout, it hasn''t fully adapted to the load. Increasing the intensity or volume before adaptation risks overtraining or injury, so maintain the same effort until recovery improves.', 2, 'dad_csv:row3') on conflict (id) do nothing;
insert into rules (id, domain, trigger_conditions, action_forces, action_vetoes, rationale, tier, source)
values ('3a4453b8-5697-4a36-8389-e2736da419b7', 'coach', '{"pain_location": "knee/upper hamstring"}'::jsonb, '["brisk walking", "light strides", "upper body exercises"]'::jsonb, '["jogging", "high-impact lower body exercise"]'::jsonb, 'When experiencing minor knee or hamstring pain, reduce lower body impact to test the injury and allow recovery. Shift focus to upper body exercises to maintain workout consistency without further aggravation.', 0, 'dad_csv:row4') on conflict (id) do nothing;
insert into rules (id, domain, trigger_conditions, action_forces, action_vetoes, rationale, tier, source)
values ('4b940cc8-e8bd-4eef-8ba2-9ca125a5a93f', 'coach', '{"subjective_feeling": "in the rhythm", "primary_activity_completed": "strides"}'::jsonb, '["abs", "upper body", "stretching"]'::jsonb, '[]'::jsonb, 'The primary running work is not a complete session on its own. It must be supplemented with core, upper body, and flexibility training for a holistic workout.', 1, 'dad_csv:row5') on conflict (id) do nothing;
insert into rules (id, domain, trigger_conditions, action_forces, action_vetoes, rationale, tier, source)
values ('50e6aa8a-cf5d-4e46-ac1e-2c9c057d5d63', 'coach', '{"condition": "obese"}'::jsonb, '["cycling", "half-court basketball"]'::jsonb, '[]'::jsonb, 'Low-impact exercises like cycling are recommended for obese individuals to protect the knees from the stress and potential injury associated with high-impact activities.', 1, 'dad_csv:row6') on conflict (id) do nothing;
insert into rules (id, domain, trigger_conditions, action_forces, action_vetoes, rationale, tier, source)
values ('7047bbba-85be-4de6-96ab-e59c9c58de4e', 'coach', '{"weather": ["hot", "cold", "raining"]}'::jsonb, '["gym training"]'::jsonb, '["outdoor training"]'::jsonb, 'When weather is adverse, indoor training is safer and more effective than battling extreme heat, cold, or rain outdoors.', 2, 'dad_csv:row7') on conflict (id) do nothing;
insert into rules (id, domain, trigger_conditions, action_forces, action_vetoes, rationale, tier, source)
values ('7f3a0310-b039-498e-9ea4-d29e50593387', 'coach', '{"fatigue_level": "high", "available_time_minutes": "<=5"}'::jsonb, '["very_light_arm_rotation", "stretching"]'::jsonb, '[]'::jsonb, 'A short, light session maintains the exercise habit. Warming up often provides enough energy to transition into a longer workout, preventing a missed day.', 2, 'dad_csv:row8') on conflict (id) do nothing;
insert into rules (id, domain, trigger_conditions, action_forces, action_vetoes, rationale, tier, source)
values ('87e1300b-8738-4700-b7df-d38d46e212d4', 'coach', '{"symptom": "muscle soreness"}'::jsonb, '["long walk (30-45 minutes)", "ab exercises", "squats", "push-ups"]'::jsonb, '["full-blown workout", "gym"]'::jsonb, 'When muscles are sore from a previous day''s exertion, avoid a high-intensity gym session to prevent over-straining. Instead, promote active recovery with low-impact cardio and foundational bodyweight exercises to aid healing.', 0, 'dad_csv:row9') on conflict (id) do nothing;
insert into rules (id, domain, trigger_conditions, action_forces, action_vetoes, rationale, tier, source)
values ('96510c1c-ef58-45ca-a6b5-7de49b69acf5', 'coach', '{"physical_state": "very tired"}'::jsonb, '[]'::jsonb, '["gym workout"]'::jsonb, 'When the body is very tired, it is more prone to injury, so you should not go to the gym.', 0, 'dad_csv:row10') on conflict (id) do nothing;
insert into rules (id, domain, trigger_conditions, action_forces, action_vetoes, rationale, tier, source)
values ('9ece2495-3f7b-4157-8c6c-eafd79c345dc', 'coach', '{"workout_history": "10-15 consecutive days of individual workouts", "psychological_state": "boredom"}'::jsonb, '["tennis", "volleyball", "basketball", "football", "team sports"]'::jsonb, '[]'::jsonb, 'Repetitive solo workouts often lead to boredom. Introducing sports provides a community or competitive element to maintain engagement and motivation.', 3, 'dad_csv:row11') on conflict (id) do nothing;
insert into rules (id, domain, trigger_conditions, action_forces, action_vetoes, rationale, tier, source)
values ('9fc2d2e3-98a3-4337-90e4-9a187c9503d9', 'coach', '{"engagement": "low", "psychological_state": "bored"}'::jsonb, '["introduce workout variation", "suggest environmental change", "recommend group or social activities", "propose nearby fitness events", "maintain 3 days/week strength training"]'::jsonb, '["routine workout"]'::jsonb, 'When an athlete is bored or disengaged, variety is the best motivation to bring them back. Introducing surprise through new workouts, environments, or social connections is critical, while still ensuring foundational strength work is completed.', 3, 'dad_csv:row12') on conflict (id) do nothing;
insert into rules (id, domain, trigger_conditions, action_forces, action_vetoes, rationale, tier, source)
values ('b08d2713-71ff-412a-b80a-4163060014ef', 'coach', '{"psychological_state": "dislikes_low_body_position"}'::jsonb, '["upper_body_exercises"]'::jsonb, '["lower_body_exercises"]'::jsonb, 'A negative mindset towards low body positions can lead to poor form, which is bad for your legs. It''s more productive to focus on the upper body instead.', 0, 'dad_csv:row13') on conflict (id) do nothing;
insert into rules (id, domain, trigger_conditions, action_forces, action_vetoes, rationale, tier, source)
values ('ca83592f-169d-4e9b-828b-2f0e56a9f0fd', 'coach', '{"user_report_day_type": "long", "time_available_minutes": ">10"}'::jsonb, '["bodyweight functional exercises", "abs", "stretching", "push-ups"]'::jsonb, '["equipment-based exercises"]'::jsonb, 'After a long day, the user is mentally tired; a simple, equipment-free workout is more achievable and prevents skipping the session. It focuses on consistency over intensity when energy is low.', 2, 'dad_csv:row14') on conflict (id) do nothing;
insert into rules (id, domain, trigger_conditions, action_forces, action_vetoes, rationale, tier, source)
values ('e8585b0d-7d88-40f0-bfcb-54b60e1af6ac', 'coach', '{"previous_workout_intensity": "high", "previous_workout_muscle_group": ["legs", "shoulders"]}'::jsonb, '["extended rest", "extended sleep"]'::jsonb, '[]'::jsonb, 'Intense workouts, especially for major muscle groups like legs or shoulders, require significant rest and sleep to allow the body to properly recover for subsequent training.', 1, 'dad_csv:row15') on conflict (id) do nothing;

-- ADDITIONAL rules: dad training log + Seerat sports-science transcript.
insert into rules (domain, trigger_conditions, action_forces, action_vetoes, rationale, tier, source)
values ('coach', '{"previous_day_activity": "strength"}'::jsonb, '["endurance / cardio", "stretching", "abs"]'::jsonb, '["heavy strength again"]'::jsonb, 'Alternate the stimulus: after a strength day, do endurance. Strength and endurance go hand in hand.', 1, 'dad_log:alternate');
insert into rules (domain, trigger_conditions, action_forces, action_vetoes, rationale, tier, source)
values ('coach', '{"previous_day_activity": "endurance"}'::jsonb, '["strength training"]'::jsonb, '[]'::jsonb, 'After an endurance day, do strength. Don''t let strength lapse — cardio-only loses muscle.', 1, 'dad_log:alternate');
insert into rules (domain, trigger_conditions, action_forces, action_vetoes, rationale, tier, source)
values ('coach', '{"days_since_strength": ">=2"}'::jsonb, '["some leg or arm strength today"]'::jsonb, '[]'::jsonb, 'Strength must not lapse more than 1-2 days or the body loosens up; keep ~3 strength days/week.', 1, 'dad_log:strength-lapse');
insert into rules (domain, trigger_conditions, action_forces, action_vetoes, rationale, tier, source)
values ('coach', '{"physical_state": "returning from layoff"}'::jsonb, '["ease back gradually", "moderate pace, build up over weeks"]'::jsonb, '["jump to max effort", "high intensity"]'::jsonb, 'Coming back after a break: even if fully recovered, do NOT jump to max — ease in to avoid injury.', 1, 'dad_log:ease-back');
insert into rules (domain, trigger_conditions, action_forces, action_vetoes, rationale, tier, source)
values ('coach', '{"physical_state": "spent"}'::jsonb, '["cut volume: 2 sets not 3"]'::jsonb, '["3 sets", "high volume"]'::jsonb, 'When the body is very spent from yesterday, reduce volume (2 sets not 3).', 2, 'dad_log:reduce-volume');
insert into rules (domain, trigger_conditions, action_forces, action_vetoes, rationale, tier, source)
values ('coach', '{"fueling": "under-fuelled"}'::jsonb, '["walk + stretching only", "keep it light"]'::jsonb, '["hard session", "high intensity", "gym workout"]'::jsonb, 'Under-fuelling/crashing OVERRIDES a good recovery score — even at 88% recovery, if he skipped meals and crashed, drop to a walk.', 0, 'dad_log:fueling-override');
insert into rules (domain, trigger_conditions, action_forces, action_vetoes, rationale, tier, source)
values ('coach', '{"injury_scare": "recent"}'::jsonb, '["recovery workout", "light + stretching"]'::jsonb, '["heavy", "high-impact"]'::jsonb, 'After an injury scare, make the next day a deliberate recovery day even if he feels recovered.', 0, 'dad_log:injury-scare');
insert into rules (domain, trigger_conditions, action_forces, action_vetoes, rationale, tier, source)
values ('coach', '{"current_day_focus": "endurance"}'::jsonb, '["run/cardio + stretching + abs"]'::jsonb, '[]'::jsonb, 'An endurance session = run + stretching + abs.', 1, 'dad_log:endurance-structure');
insert into rules (domain, trigger_conditions, action_forces, action_vetoes, rationale, tier, source)
values ('coach', '{"current_day_focus": "upper_body"}'::jsonb, '["do abs BETWEEN the upper-body sets"]'::jsonb, '[]'::jsonb, 'Weave abs between upper-body sets: keeps the core toned AND gives the arms active rest so they don''t burn out.', 2, 'dad_log:abs-between');
insert into rules (domain, trigger_conditions, action_forces, action_vetoes, rationale, tier, source)
values ('coach', '{"current_day_focus": "strength"}'::jsonb, '["warm up first (a few minutes easy cycling)"]'::jsonb, '[]'::jsonb, 'Warm up (e.g. a few minutes cycling) before strength.', 2, 'dad_log:warmup');
insert into rules (domain, trigger_conditions, action_forces, action_vetoes, rationale, tier, source)
values ('sports_science', '{"physical_state": "exhausted"}'::jsonb, '["mobility work", "keep the body light"]'::jsonb, '["hard load"]'::jsonb, 'Seerat: if sleep wasn''t full, first ask how exhausted; if they can''t lift anything, do mobility so it improves and the body stays light.', 1, 'seerat:recovery');
insert into rules (domain, trigger_conditions, action_forces, action_vetoes, rationale, tier, source)
values ('sports_science', '{"previous_rpe": "high"}'::jsonb, '["reduce load / volume today"]'::jsonb, '["another hard session"]'::jsonb, 'Seerat load management: a high RPE (8-9) last session means go lighter next — don''t over-exert on top of it.', 2, 'seerat:RPE-load');
insert into rules (domain, trigger_conditions, action_forces, action_vetoes, rationale, tier, source)
values ('sports_science', '{"physical_state": "good", "sleep_quality": "good"}'::jsonb, '["do the full planned session"]'::jsonb, '[]'::jsonb, 'Seerat: good recovery + 8-9h sleep + ''dil kar raha hai'' → they can do the full planned workout.', 2, 'seerat:readiness');
insert into rules (domain, trigger_conditions, action_forces, action_vetoes, rationale, tier, source)
values ('sports_science', '{"current_day_focus": "strength"}'::jsonb, '["balance the session: ~2 upper, 2 lower, 2 core, 2 stability"]'::jsonb, '["hammering one muscle only"]'::jsonb, 'Seerat: hit the OVERALL body in a session (2 upper/2 lower/2 core/2 stability), not one isolated muscle.', 1, 'seerat:full-body');
insert into rules (domain, trigger_conditions, action_forces, action_vetoes, rationale, tier, source)
values ('sports_science', '{"psychological_state": "unmotivated"}'::jsonb, '["lower the bar: ''just 2-3 quick things, wrap up fast''", "add something interesting (e.g. agility)"]'::jsonb, '[]'::jsonb, 'Seerat motivation (general pop): when they don''t feel like it, shrink the ask to get them moving, then build interest.', 3, 'seerat:motivation');
insert into rules (domain, trigger_conditions, action_forces, action_vetoes, rationale, tier, source)
values ('sports_science', '{"physical_state": "breathless"}'::jsonb, '["reduce repetitions", "reduce load"]'::jsonb, '["continue heavy"]'::jsonb, 'Seerat safety: if breathing isn''t easy or form is breaking down, cut reps and load.', 0, 'seerat:safety');
insert into rules (domain, trigger_conditions, action_forces, action_vetoes, rationale, tier, source)
values ('sports_science', '{"session_phase": "ending"}'::jsonb, '["ask their RPE 1-10 for load management"]'::jsonb, '[]'::jsonb, 'Seerat: at the end of the session, get their RPE (1-10) so the next session''s load can be set.', 2, 'seerat:RPE-ask');
