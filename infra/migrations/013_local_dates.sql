-- Proper LOCAL calendar dates on every record, so the coach reasons about
-- "yesterday / last week" from ABSOLUTE dates (compared to today's date it now
-- receives), not fragile relative labels. Timestamps are stored in UTC; this adds
-- a local_date derived in the user's timezone (Asia/Kolkata), and BACKFILLS all
-- existing rows retroactively. Run once in Supabase (project pnbrjxgmaulijamhcyik).

alter table nutrition_log     add column if not exists local_date date;
alter table coaching_sessions add column if not exists local_date date;
alter table conversations     add column if not exists local_date date;
alter table planned_workouts  add column if not exists local_date date;

-- Retro backfill: convert each row's UTC timestamp into the user's local date.
update nutrition_log     set local_date = (logged_at  at time zone 'Asia/Kolkata')::date where local_date is null;
update coaching_sessions set local_date = (started_at at time zone 'Asia/Kolkata')::date where local_date is null;
update conversations     set local_date = (started_at at time zone 'Asia/Kolkata')::date where local_date is null;
update planned_workouts  set local_date = (created_at at time zone 'Asia/Kolkata')::date where local_date is null;
