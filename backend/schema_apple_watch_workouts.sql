-- ============================================================================
-- APPLE WATCH WORKOUTS - COMPREHENSIVE SYNC
-- ============================================================================
-- Created: 2026-04-03
-- Purpose: Sync Apple Watch workouts from HealthKit to Supabase
--          Stores ALL workout metrics for Dad OS analysis and learning
-- ============================================================================

-- ----------------------------------------------------------------------------
-- TABLE: apple_watch_workouts
-- ----------------------------------------------------------------------------
-- Stores complete workout data from HealthKit
-- Supports all workout types with sport-specific metrics
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS apple_watch_workouts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL,

  -- HealthKit Identifiers
  healthkit_uuid TEXT UNIQUE NOT NULL,  -- HKWorkout.uuid.uuidString (for deduplication)

  -- Basic Workout Info
  workout_name TEXT NOT NULL,           -- "Running", "Cycling", "Strength Training"
  workout_type TEXT,                    -- HKWorkoutActivityType raw value
  is_indoor BOOLEAN DEFAULT false,

  -- Timing
  start_date TIMESTAMP NOT NULL,
  end_date TIMESTAMP NOT NULL,
  duration_seconds FLOAT NOT NULL,

  -- Basic Metrics (All Workouts)
  active_calories FLOAT,
  avg_hr FLOAT,                         -- bpm
  max_hr FLOAT,                         -- bpm
  min_hr FLOAT,                         -- bpm

  -- Distance (if applicable)
  distance_meters FLOAT,

  -- Running-Specific Metrics
  avg_cadence FLOAT,                    -- steps/min for running, RPM for cycling
  avg_stride_length FLOAT,              -- meters
  avg_oscillation_cm FLOAT,             -- vertical oscillation
  avg_gct_ms FLOAT,                     -- ground contact time (ms)
  avg_power_watts FLOAT,                -- running or cycling power

  -- Swimming-Specific
  total_strokes FLOAT,

  -- Raw Metrics JSON (for future expansion)
  raw_metrics JSONB DEFAULT '{}'::jsonb,

  -- Workout Annotations (PHASE 6C)
  voice_notes TEXT,                      -- User's voice annotation about the workout
  notes_added_at TIMESTAMP,              -- When annotation was added

  -- Sync Metadata
  synced_at TIMESTAMP DEFAULT NOW(),
  created_at TIMESTAMP DEFAULT NOW(),

  -- Indexes
  CONSTRAINT fk_user FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE
);

-- Indexes for fast querying
CREATE INDEX IF NOT EXISTS idx_apple_watch_workouts_user_date
  ON apple_watch_workouts(user_id, start_date DESC);

CREATE INDEX IF NOT EXISTS idx_apple_watch_workouts_healthkit_uuid
  ON apple_watch_workouts(healthkit_uuid);

CREATE INDEX IF NOT EXISTS idx_apple_watch_workouts_workout_name
  ON apple_watch_workouts(user_id, workout_name, start_date DESC);

COMMENT ON TABLE apple_watch_workouts IS 'Apple Watch workouts synced from HealthKit with comprehensive metrics';

-- ----------------------------------------------------------------------------
-- VIEW: recent_workouts (Last 7 days summary)
-- ----------------------------------------------------------------------------

CREATE OR REPLACE VIEW recent_workouts_summary AS
SELECT
  user_id,
  workout_name,
  COUNT(*) as workout_count,
  SUM(duration_seconds) / 3600 as total_hours,
  SUM(active_calories) as total_calories,
  AVG(avg_hr) as avg_heart_rate,
  DATE(start_date) as workout_date
FROM apple_watch_workouts
WHERE start_date >= NOW() - INTERVAL '7 days'
GROUP BY user_id, workout_name, DATE(start_date)
ORDER BY workout_date DESC, workout_count DESC;

COMMENT ON VIEW recent_workouts_summary IS 'Last 7 days workout summary by type';

-- ----------------------------------------------------------------------------
-- VERIFICATION QUERIES
-- ----------------------------------------------------------------------------

-- Check table exists
SELECT table_name, column_name, data_type
FROM information_schema.columns
WHERE table_name = 'apple_watch_workouts'
ORDER BY ordinal_position;

-- Count workouts (should be 0 initially)
SELECT COUNT(*) as workout_count FROM apple_watch_workouts;

-- ============================================================================
-- END OF SCHEMA
-- ============================================================================
