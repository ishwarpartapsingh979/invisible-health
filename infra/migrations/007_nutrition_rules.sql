-- Nutrition rules (domain=nutrition) — from rules-source/nutrition/*.md
-- (my-eating-guide.md + nutrition-master-prompt.md). Run AFTER 006.
-- Clear + reseed nutrition domain so this file is the source of truth:
delete from rules where domain = 'nutrition';
insert into rules (domain, trigger_conditions, action_forces, action_vetoes, rationale, tier, source)
values ('nutrition', '{"is_refined": "yes"}'::jsonb, '["swap to whole-grain / millet (bajra, jowar, multigrain, oats)"]'::jsonb, '["refined base: maida / white bread / cornflour / big white-rice load"]'::jsonb, '2-check rule: if the base is a refined carb, ''no added sugar'' does NOT rescue it.', 0, 'eating-guide:2-check');
insert into rules (domain, trigger_conditions, action_forces, action_vetoes, rationale, tier, source)
values ('nutrition', '{"is_fried": "yes"}'::jsonb, '["air-fry or bake instead"]'::jsonb, '["fried"]'::jsonb, '2-check rule: if it''s fried, ''no added sugar'' does NOT rescue it.', 0, 'eating-guide:2-check');
insert into rules (domain, trigger_conditions, action_forces, action_vetoes, rationale, tier, source)
values ('nutrition', '{"contains_sugar": "yes"}'::jsonb, '["pick the no-added-sugar version; whole LOW-sugar fruit (berries/papaya/guava/apple), not juice"]'::jsonb, '["added sugar", "jaggery", "honey", "fruit juice (liquid sugar, no fibre)"]'::jsonb, 'Treat jaggery/honey/fruit-juice as sugar. Whole fruit passes; juice fails in spirit.', 0, 'master-prompt:sugar');
insert into rules (domain, trigger_conditions, action_forces, action_vetoes, rationale, tier, source)
values ('nutrition', '{}'::jsonb, '["protein at EVERY meal \u2014 front-load it at breakfast"]'::jsonb, '[]'::jsonb, 'Protein each meal is the #1 lever for muscle + satiety; biggest WHOOP-age driver is lean body mass.', 1, 'eating-guide:levers');
insert into rules (domain, trigger_conditions, action_forces, action_vetoes, rationale, tier, source)
values ('nutrition', '{}'::jsonb, '["lean-up any dish: boost protein, strip hidden fat/refined-carb \u2014 leaner cut, MEASURED 1 tsp oil (never free-pour), no cream, smaller refined carb, more veg (egg whites+1 yolk, toned-milk paneer, besan into atta, air-fry)"]'::jsonb, '["free-pouring oil", "cream"]'::jsonb, 'The lean-up principle: keep/boost protein and strip hidden fat + refined-carb calories from every dish.', 1, 'master-prompt:lean-up');
insert into rules (domain, trigger_conditions, action_forces, action_vetoes, rationale, tier, source)
values ('nutrition', '{"goal": "recomp"}'::jsonb, '["protein HIGH", "calories MODERATE \u2014 slight deficit, enough to train + recover"]'::jsonb, '["calorie surplus", "crash dieting"]'::jsonb, 'Goal is body recomposition (fat loss + build muscle): not bulking, not crash dieting.', 1, 'eating-guide:goal');
insert into rules (domain, trigger_conditions, action_forces, action_vetoes, rationale, tier, source)
values ('nutrition', '{"training_day": "yes"}'::jsonb, '["fuel training days FULLY \u2014 never train depleted; balance calories across the WEEK, don''t punish the day after a heavy one"]'::jsonb, '["cutting hard on a training day"]'::jsonb, 'Master prompt: fuel training days fully; balance calories across the week, not by punishing the next day.', 1, 'master-prompt:fuel-training');
insert into rules (domain, trigger_conditions, action_forces, action_vetoes, rationale, tier, source)
values ('nutrition', '{"is_late": "yes"}'::jsonb, '["keep dinner lighter, 2-3 hrs before sleep; skip heavy carbs if late"]'::jsonb, '["very late dinner"]'::jsonb, 'Dinner lighter + earlier helps his short sleep (5:41 avg, a WHOOP-age driver).', 1, 'eating-guide:dinner');
insert into rules (domain, trigger_conditions, action_forces, action_vetoes, rationale, tier, source)
values ('nutrition', '{}'::jsonb, '["watch CUMULATIVE daily sugar across juice + fruit + drinks + sauces, not just per item"]'::jsonb, '[]'::jsonb, 'Sugar adds up across the day; default fruit = low-sugar (berries/papaya/guava/apple).', 2, 'master-prompt:cumulative-sugar');
insert into rules (domain, trigger_conditions, action_forces, action_vetoes, rationale, tier, source)
values ('nutrition', '{}'::jsonb, '["2.5-3 L water daily; more on training/sweat days"]'::jsonb, '[]'::jsonb, 'Nutritionist golden rule: hydration.', 2, 'eating-guide:golden-rules');
insert into rules (domain, trigger_conditions, action_forces, action_vetoes, rationale, tier, source)
values ('nutrition', '{"need": "protein low-cal"}'::jsonb, '["plain whey scoop in water (~25g/120cal)", "Epigamia plain Turbo (17g)", "boiled eggs", "paneer cubes"]'::jsonb, '[]'::jsonb, 'Best protein-per-calorie fixes, vetted.', 2, 'eating-guide:toolkit');
insert into rules (domain, trigger_conditions, action_forces, action_vetoes, rationale, tier, source)
values ('nutrition', '{"product": "energy bar"}'::jsonb, '["skip for fat loss (Yoga Bar / True Elements / Mojo = low protein, date/fig sugar)"]'::jsonb, '["low-protein energy bars during fat loss"]'::jsonb, 'Vetted: ''energy bars'' are low-protein, sugar-heavy — skip for fat loss.', 2, 'eating-guide:bars');
insert into rules (domain, trigger_conditions, action_forces, action_vetoes, rationale, tier, source)
values ('nutrition', '{"craving": "sweet"}'::jsonb, '["Epigamia Turbo yogurt (15g protein, ~100cal, stevia) + berries \u2014 #1", "Whole Truth MINI bar (~120cal)", "a square of 85% dark chocolate (~50cal)"]'::jsonb, '[]'::jsonb, 'Vetted sweet-craving picks ranked for fat loss.', 3, 'eating-guide:toolkit');
insert into rules (domain, trigger_conditions, action_forces, action_vetoes, rationale, tier, source)
values ('nutrition', '{"craving": "crunchy"}'::jsonb, '["roasted makhana", "roasted chana", "groundnuts"]'::jsonb, '[]'::jsonb, 'Vetted crunchy/salty craving swaps.', 3, 'eating-guide:toolkit');
insert into rules (domain, trigger_conditions, action_forces, action_vetoes, rationale, tier, source)
values ('nutrition', '{"product": "RiteBite Max Protein"}'::jsonb, '["emergency/travel only (maltitol -> bloating, ~360-400 cal)"]'::jsonb, '[]'::jsonb, 'Vetted: RiteBite is more protein but maltitol-sweetened + high cal — not a daily strategy.', 3, 'eating-guide:bars');
