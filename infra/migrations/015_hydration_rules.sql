-- Hydration best-practice rules (#24). The one existing rule is just a daily
-- volume target; these add HOW to hydrate across the day (timing, workout,
-- electrolytes, sleep). Drafted from sports-nutrition best practice — FLAG for the
-- nutritionist to confirm/adjust (quantities, electrolyte brand). domain=nutrition.
-- Reseed just these so this file is the source of truth. Run AFTER 007.
delete from rules where source like 'hydration:%';

-- Always-on daily habits (trigger {} = fires for general hydration guidance).
insert into rules (domain, trigger_conditions, action_forces, action_vetoes, rationale, tier, source)
values ('nutrition', '{}'::jsonb,
        '["start the day with a glass of water on waking (rehydrate after sleep)", "sip 2.5-3 L spread ACROSS the day, don''t chug it all at once", "water between meals; go easy on large amounts DURING a meal so you don''t dilute digestion"]'::jsonb,
        '[]'::jsonb,
        'Hydration is about timing + spread, not just total volume; steady intake beats gulping.',
        2, 'hydration:daily');

-- Training-day hydration.
insert into rules (domain, trigger_conditions, action_forces, action_vetoes, rationale, tier, source)
values ('nutrition', '{"training_day": "yes"}'::jsonb,
        '["300-500 ml water ~30 min BEFORE the session", "sip regularly DURING longer/sweaty sessions (every 15-20 min)", "rehydrate after: roughly 1.5x the fluid you sweated out"]'::jsonb,
        '[]'::jsonb,
        'Fuel hydration around training so performance + recovery aren''t limited by fluid loss.',
        2, 'hydration:training');

-- Heavy sweat / hot weather → electrolytes (relevant in Indian heat).
insert into rules (domain, trigger_conditions, action_forces, action_vetoes, rationale, tier, source)
values ('nutrition', '{"weather": "hot"}'::jsonb,
        '["add electrolytes on heavy-sweat / hot days (a pinch of salt + lemon, or an electrolyte mix), not just plain water", "watch for dark urine / headache as under-hydration signs"]'::jsonb,
        '[]'::jsonb,
        'Plain water alone on big-sweat days can leave you low on sodium/electrolytes.',
        2, 'hydration:electrolytes');

-- Evening: taper fluids for sleep (ties to his short-sleep problem).
insert into rules (domain, trigger_conditions, action_forces, action_vetoes, rationale, tier, source)
values ('nutrition', '{"is_late": "yes"}'::jsonb,
        '["ease off large fluid volumes in the last ~1.5 hrs before bed so you''re not woken to pee (protects the already-short sleep)"]'::jsonb,
        '[]'::jsonb,
        'Late heavy fluids fragment sleep; he already runs short (~5:41).',
        3, 'hydration:evening');
