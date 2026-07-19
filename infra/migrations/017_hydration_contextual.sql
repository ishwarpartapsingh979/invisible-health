-- Make hydration CONTEXTUAL (Ishwar hates hydration nagging). Drop the always-on
-- daily rule (trigger {}) so the coach doesn't bring up water unprompted. The
-- training-day / hot-day / evening hydration rules stay — they only fire in
-- context (or when he asks). Run once in Supabase.
delete from rules where source = 'hydration:daily';
