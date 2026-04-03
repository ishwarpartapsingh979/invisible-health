-- ============================================================================
-- DAD OS + EXERCISEDB INTEGRATION - DATABASE SCHEMA
-- ============================================================================
-- Created: 2026-04-03
-- Purpose: Enable Dad's rules to intelligently select exercises and learn
--          from user preferences over time
-- ============================================================================

-- ----------------------------------------------------------------------------
-- TABLE 1: exercises (Open-source ExerciseDB mirror)
-- ----------------------------------------------------------------------------
-- Stores 800+ exercises from yuhonas/free-exercise-db
-- Enables Dad to suggest specific exercises based on his guidance
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS exercises (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  force TEXT,  -- 'pull', 'push', 'static'
  level TEXT,  -- 'beginner', 'intermediate', 'expert'
  mechanic TEXT,  -- 'compound', 'isolation'
  equipment TEXT,  -- 'body only', 'barbell', 'dumbbell', etc
  primary_muscles JSONB NOT NULL DEFAULT '[]'::jsonb,
  secondary_muscles JSONB DEFAULT '[]'::jsonb,
  instructions JSONB DEFAULT '[]'::jsonb,
  category TEXT,
  images JSONB DEFAULT '[]'::jsonb,
  created_at TIMESTAMP DEFAULT NOW()
);

-- Indexes for fast filtering
CREATE INDEX IF NOT EXISTS idx_exercises_equipment ON exercises(equipment);
CREATE INDEX IF NOT EXISTS idx_exercises_primary_muscles ON exercises USING GIN (primary_muscles);
CREATE INDEX IF NOT EXISTS idx_exercises_level ON exercises(level);
CREATE INDEX IF NOT EXISTS idx_exercises_category ON exercises(category);

COMMENT ON TABLE exercises IS 'Open-source exercise library (800+ exercises from free-exercise-db)';

-- ----------------------------------------------------------------------------
-- TABLE 2: user_exercise_history (What user actually did)
-- ----------------------------------------------------------------------------
-- Logs every exercise performed by user
-- Links to Dad's rule that triggered it
-- Tracks performance for progressive overload
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS user_exercise_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL,
  workout_date DATE NOT NULL,

  -- Dad's rule context
  dad_rule_id UUID,  -- References dad_os_rules.id
  dad_guidance TEXT,  -- "triceps", "upper body", "squats", etc

  -- Exercise performed
  exercise_id TEXT,  -- References exercises.id
  exercise_name TEXT NOT NULL,

  -- Performance data
  sets INT,
  reps INT,
  weight_kg FLOAT,

  -- Feedback (collected post-workout)
  quality_rating INT CHECK (quality_rating >= 1 AND quality_rating <= 5),
  next_day_soreness INT CHECK (next_day_soreness >= 0 AND next_day_soreness <= 10),

  -- Selection metadata (for learning)
  was_recommended BOOLEAN DEFAULT false,  -- Did system suggest this?
  was_override BOOLEAN DEFAULT false,  -- Did user choose different exercise?

  created_at TIMESTAMP DEFAULT NOW()
);

-- Indexes for common queries
CREATE INDEX IF NOT EXISTS idx_user_exercise_history_user_date
  ON user_exercise_history(user_id, workout_date DESC);
CREATE INDEX IF NOT EXISTS idx_user_exercise_history_guidance
  ON user_exercise_history(user_id, dad_guidance, workout_date DESC);
CREATE INDEX IF NOT EXISTS idx_user_exercise_history_exercise
  ON user_exercise_history(exercise_id);

COMMENT ON TABLE user_exercise_history IS 'Complete workout history - tracks every exercise performed';

-- ----------------------------------------------------------------------------
-- TABLE 3: user_exercise_preferences (What user likes/dislikes)
-- ----------------------------------------------------------------------------
-- Learned preferences based on user choices and feedback
-- Powers intelligent exercise ranking
-- Example: "User prefers overhead extensions over kickbacks for triceps"
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS user_exercise_preferences (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL,
  muscle_group TEXT NOT NULL,  -- "triceps", "chest", "back", etc

  exercise_id TEXT NOT NULL,  -- References exercises.id
  exercise_name TEXT,

  -- Learned preference strength (0 = dislike, 1 = love)
  preference_score FLOAT DEFAULT 0.5 CHECK (preference_score >= 0 AND preference_score <= 1),

  -- Learning metrics
  times_chosen INT DEFAULT 0,  -- How many times user selected this
  times_recommended INT DEFAULT 0,  -- How many times system suggested this
  avg_quality_rating FLOAT,  -- Average of quality_rating from history
  avg_soreness FLOAT,  -- Average soreness (lower is better)

  last_performed DATE,

  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),

  UNIQUE(user_id, muscle_group, exercise_id)
);

-- Indexes for preference lookup
CREATE INDEX IF NOT EXISTS idx_user_exercise_preferences_lookup
  ON user_exercise_preferences(user_id, muscle_group, preference_score DESC);

COMMENT ON TABLE user_exercise_preferences IS 'Learned user preferences - which exercises user likes/dislikes per muscle group';

-- ----------------------------------------------------------------------------
-- TABLE 4: rule_firing_events (When and how Dad's rules fire)
-- ----------------------------------------------------------------------------
-- Tracks every time a Dad OS rule is evaluated
-- Records user's response (followed vs overrode)
-- Calculates rule effectiveness over time
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS rule_firing_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL,
  rule_id UUID NOT NULL,  -- References dad_os_rules.id
  fired_at TIMESTAMP DEFAULT NOW(),

  -- Full context when rule fired (for analysis)
  trigger_context JSONB,  -- {hrv: 35, rhr: 65, pain: "knee", etc}

  -- User decision
  user_action TEXT CHECK (user_action IN ('followed', 'overrode', 'modified')),
  override_reason TEXT,
  conversation_transcript TEXT,  -- Gemini Flash Live conversation

  -- Outcome tracking (populated 24h later)
  injury_reported BOOLEAN,
  workout_quality_rating INT CHECK (workout_quality_rating >= 1 AND workout_quality_rating <= 5),
  next_day_soreness INT CHECK (next_day_soreness >= 0 AND next_day_soreness <= 10),

  -- Effectiveness calculation
  rule_was_helpful BOOLEAN,  -- Did rule prevent injury or improve outcome?

  created_at TIMESTAMP DEFAULT NOW()
);

-- Indexes for analytics
CREATE INDEX IF NOT EXISTS idx_rule_firing_events_rule
  ON rule_firing_events(rule_id, rule_was_helpful);
CREATE INDEX IF NOT EXISTS idx_rule_firing_events_user
  ON rule_firing_events(user_id, fired_at DESC);

COMMENT ON TABLE rule_firing_events IS 'Rule firing log - tracks when rules fire and their effectiveness';

-- ----------------------------------------------------------------------------
-- TABLE 5: gemini_conversations (Voice conversation sessions)
-- ----------------------------------------------------------------------------
-- Tracks Gemini Flash Live voice conversations
-- Stores full conversation history for analysis
-- Links conversations to outcomes (rule followed, workout completed, etc)
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS gemini_conversations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL,
  session_id TEXT NOT NULL UNIQUE,

  started_at TIMESTAMP DEFAULT NOW(),
  ended_at TIMESTAMP,

  -- Full conversation transcript
  conversation_history JSONB DEFAULT '[]'::jsonb,
  -- Array of {role: "user"|"assistant", message: "...", timestamp: "..."}

  -- Conversation outcome
  outcome TEXT,  -- "followed_rule", "overrode", "workout_completed", "cancelled"

  created_at TIMESTAMP DEFAULT NOW()
);

-- Indexes for session lookup
CREATE INDEX IF NOT EXISTS idx_gemini_conversations_user
  ON gemini_conversations(user_id, started_at DESC);
CREATE INDEX IF NOT EXISTS idx_gemini_conversations_session
  ON gemini_conversations(session_id);

COMMENT ON TABLE gemini_conversations IS 'Gemini Flash Live voice conversation sessions';

-- ----------------------------------------------------------------------------
-- VERIFICATION QUERIES
-- ----------------------------------------------------------------------------
-- Run these after creating tables to verify structure

-- List all tables
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name IN ('exercises', 'user_exercise_history', 'user_exercise_preferences', 'rule_firing_events', 'gemini_conversations')
ORDER BY table_name;

-- Count rows (should be 0 initially)
SELECT
  'exercises' as table_name, COUNT(*) as row_count FROM exercises
UNION ALL
SELECT 'user_exercise_history', COUNT(*) FROM user_exercise_history
UNION ALL
SELECT 'user_exercise_preferences', COUNT(*) FROM user_exercise_preferences
UNION ALL
SELECT 'rule_firing_events', COUNT(*) FROM rule_firing_events
UNION ALL
SELECT 'gemini_conversations', COUNT(*) FROM gemini_conversations;

-- ============================================================================
-- END OF SCHEMA
-- ============================================================================
