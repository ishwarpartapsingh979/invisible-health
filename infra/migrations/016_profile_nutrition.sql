-- Onboarding now captures NUTRITION context too (not just training), so the coach
-- personalises food advice from day one. Add the nutrition columns to user_profiles.
-- Run once in Supabase (project pnbrjxgmaulijamhcyik).

alter table user_profiles add column if not exists diet_type         text;  -- veg / non-veg / vegan / eggetarian
alter table user_profiles add column if not exists food_avoid        text;  -- allergies / restrictions
alter table user_profiles add column if not exists food_likes        text;
alter table user_profiles add column if not exists food_dislikes     text;
alter table user_profiles add column if not exists meals_per_day      text;
alter table user_profiles add column if not exists cooks_or_eats_out  text;
alter table user_profiles add column if not exists nutrition_goal     text;  -- fat loss / build muscle / recomp / maintain
