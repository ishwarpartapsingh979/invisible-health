-- Nutrition VARIETY / CAPS rules (domain=nutrition, preference tier 3).
-- Source: rules-source/nutrition_source.md — nutritionist wants proteins rotated
-- (paneer ~3x/wk, chicken ~2x/wk) and greens + legumes rotated (no day-to-day
-- repeats). The agent computes the counts (_frequency_facts) and sets the flags
-- protein_over_cap / repeats_recent; these rules turn that into guidance.
-- Preference tier (3): they NEVER override a training or safety call. Run AFTER 007.
-- Clear + reseed just these two so this file stays the source of truth:
delete from rules where source like 'rotation:%';

insert into rules (domain, trigger_conditions, action_forces, action_vetoes, rationale, tier, source)
values ('nutrition', '{"protein_over_cap": "yes"}'::jsonb,
        '["you have already hit this protein''s weekly count — rotate to a different protein today (chicken/fish/dal/eggs/tofu) to keep it varied"]'::jsonb,
        '[]'::jsonb,
        'Nutritionist: rotate proteins — paneer ~3x/week, chicken ~2x/week; do not repeat the same protein all week.',
        3, 'rotation:protein-cap');

insert into rules (domain, trigger_conditions, action_forces, action_vetoes, rationale, tier, source)
values ('nutrition', '{"repeats_recent": "yes"}'::jsonb,
        '["you had this same green/legume very recently — rotate to a different one today (palak, broccoli, methi, sarson, cabbage, lauki / rajma, kala chana, masoor, lobia, moong)"]'::jsonb,
        '[]'::jsonb,
        'Nutritionist: rotate greens and legumes, no back-to-back repeats — variety across the week.',
        3, 'rotation:veg-repeat');
