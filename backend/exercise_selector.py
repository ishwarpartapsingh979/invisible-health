#!/usr/bin/env python3
"""
Exercise Selection Engine
=========================
Intelligent exercise selection based on Dad's high-level guidance.

Dad says: "triceps" → System selects: Overhead Extension, Close-grip Push-up, etc.
Dad says: "upper body" → System selects: variety of chest, back, shoulders
Dad says: "squats" → System selects: specific squat variations

Ranking Algorithm:
1. Freshness (not done recently)
2. User preferences (learned 0-1 score)
3. Recovery appropriateness (matches current state)
4. Progressive overload (suitable for current level)
5. Variety (avoid same exercises too frequently)

Used by: Gemini Flash Live conversation & agent_engine.py
"""

import os
from datetime import datetime, timedelta
from typing import Dict, List, Any, Optional, Tuple
from supabase import create_client, Client


class ExerciseSelector:
    """
    Intelligent exercise selector with preference learning
    """

    # Mapping from Dad's guidance to muscle groups in ExerciseDB
    GUIDANCE_TO_MUSCLES = {
        # Specific muscle groups
        'triceps': ['triceps'],
        'biceps': ['biceps'],
        'chest': ['chest'],
        'back': ['lats', 'middle back', 'lower back'],
        'shoulders': ['shoulders'],
        'abs': ['abdominals'],
        'core': ['abdominals'],
        'legs': ['quadriceps', 'hamstrings', 'glutes'],
        'quads': ['quadriceps'],
        'hamstrings': ['hamstrings'],
        'glutes': ['glutes'],
        'calves': ['calves'],

        # Compound categories
        'upper body': ['chest', 'lats', 'shoulders', 'triceps', 'biceps'],
        'lower body': ['quadriceps', 'hamstrings', 'glutes', 'calves'],

        # Exercise types
        'squats': ['quadriceps', 'glutes'],  # Will filter by name too
        'push-ups': ['chest', 'triceps'],
        'pull-ups': ['lats', 'biceps'],
        'stretching': []  # Special case
    }

    # Default preference score for new exercises
    DEFAULT_PREFERENCE = 0.5

    def __init__(self, supabase: Optional[Client] = None):
        """
        Initialize selector with Supabase client

        Args:
            supabase: Optional Supabase client (will create if not provided)
        """
        if supabase:
            self.supabase = supabase
        else:
            url = os.environ.get("SUPABASE_URL")
            key = os.environ.get("SUPABASE_SERVICE_KEY")
            if not url or not key:
                raise ValueError("Missing Supabase credentials")
            self.supabase = create_client(url, key)

    def map_guidance_to_muscles(self, guidance: str) -> List[str]:
        """
        Map Dad's guidance to ExerciseDB muscle groups

        Args:
            guidance: Dad's guidance (e.g., "triceps", "upper body", "squats")

        Returns:
            List of muscle groups to query
        """
        guidance_lower = guidance.lower().strip()

        # Direct mapping
        if guidance_lower in self.GUIDANCE_TO_MUSCLES:
            return self.GUIDANCE_TO_MUSCLES[guidance_lower]

        # Fuzzy matching for variations
        for key, muscles in self.GUIDANCE_TO_MUSCLES.items():
            if key in guidance_lower or guidance_lower in key:
                return muscles

        # Default: treat as muscle group name
        return [guidance_lower]

    def get_exercises_for_guidance(
        self,
        guidance: str,
        equipment_available: Optional[List[str]] = None,
        limit: int = 50
    ) -> List[Dict[str, Any]]:
        """
        Query exercises from ExerciseDB based on guidance

        Args:
            guidance: Dad's guidance ("triceps", "upper body", etc.)
            equipment_available: List of available equipment (e.g., ["barbell", "dumbbell"])
            limit: Maximum number of exercises to return

        Returns:
            List of exercise dictionaries from exercises table
        """
        muscle_groups = self.map_guidance_to_muscles(guidance)

        if not muscle_groups:
            # Special case: stretching (no specific muscle group)
            if 'stretch' in guidance.lower():
                result = self.supabase.table('exercises') \
                    .select('*') \
                    .ilike('name', '%stretch%') \
                    .limit(limit) \
                    .execute()
                return result.data

        # Query exercises by muscle group
        exercises = []

        for muscle in muscle_groups:
            # Use JSONB contains operator for array field
            result = self.supabase.table('exercises') \
                .select('*') \
                .contains('primary_muscles', [muscle]) \
                .limit(limit) \
                .execute()

            exercises.extend(result.data)

        # Filter by equipment if specified
        if equipment_available:
            equipment_lower = [e.lower() for e in equipment_available]
            exercises = [
                e for e in exercises
                if e.get('equipment', '').lower() in equipment_lower
            ]

        # Special case: filter by name for specific guidance
        guidance_lower = guidance.lower()
        if 'squat' in guidance_lower:
            exercises = [e for e in exercises if 'squat' in e.get('name', '').lower()]
        elif 'push' in guidance_lower and 'up' in guidance_lower:
            exercises = [e for e in exercises if 'push' in e.get('name', '').lower()]

        # Remove duplicates (same exercise may appear for multiple muscles)
        seen_ids = set()
        unique_exercises = []
        for ex in exercises:
            if ex['id'] not in seen_ids:
                seen_ids.add(ex['id'])
                unique_exercises.append(ex)

        return unique_exercises[:limit]

    def get_user_preference(
        self,
        user_id: str,
        muscle_group: str,
        exercise_id: str
    ) -> float:
        """
        Get user's learned preference score for an exercise

        Args:
            user_id: User UUID
            muscle_group: Muscle group being targeted
            exercise_id: Exercise ID

        Returns:
            Preference score (0-1), defaults to 0.5 if not found
        """
        result = self.supabase.table('user_exercise_preferences') \
            .select('preference_score') \
            .eq('user_id', user_id) \
            .eq('muscle_group', muscle_group) \
            .eq('exercise_id', exercise_id) \
            .execute()

        if result.data:
            return result.data[0]['preference_score']

        return self.DEFAULT_PREFERENCE

    def get_exercise_freshness_score(
        self,
        user_id: str,
        exercise_id: str,
        days_lookback: int = 30
    ) -> float:
        """
        Calculate freshness score based on when exercise was last performed

        Args:
            user_id: User UUID
            exercise_id: Exercise ID
            days_lookback: How far back to look

        Returns:
            Freshness score (0-1), where 1 = never done, 0 = done today
        """
        cutoff = (datetime.now() - timedelta(days=days_lookback)).date().isoformat()

        result = self.supabase.table('user_exercise_history') \
            .select('workout_date') \
            .eq('user_id', user_id) \
            .eq('exercise_id', exercise_id) \
            .gte('workout_date', cutoff) \
            .order('workout_date', desc=True) \
            .limit(1) \
            .execute()

        if not result.data:
            return 1.0  # Never done = maximum freshness

        last_performed = datetime.fromisoformat(result.data[0]['workout_date'])
        days_since = (datetime.now() - last_performed).days

        # Linear decay: 1.0 at 30 days, 0.0 at 0 days
        freshness = min(1.0, days_since / days_lookback)

        return freshness

    def rank_exercises(
        self,
        user_id: str,
        exercises: List[Dict[str, Any]],
        muscle_group: str,
        user_state: Optional[Dict[str, Any]] = None
    ) -> List[Tuple[Dict[str, Any], float]]:
        """
        Rank exercises using multi-factor algorithm

        Args:
            user_id: User UUID
            exercises: List of exercises from get_exercises_for_guidance()
            muscle_group: Target muscle group for preference lookup
            user_state: Optional state dict with recovery info

        Returns:
            List of (exercise, score) tuples, sorted by score (highest first)
        """
        scored_exercises = []

        for exercise in exercises:
            exercise_id = exercise['id']

            # 1. Freshness score (40% weight)
            freshness = self.get_exercise_freshness_score(user_id, exercise_id)

            # 2. User preference (40% weight)
            preference = self.get_user_preference(user_id, muscle_group, exercise_id)

            # 3. Recovery appropriateness (20% weight)
            recovery_score = 0.5  # Default neutral

            if user_state:
                inferred_state = user_state.get('inferred_physical_state', 'normal')
                equipment = exercise.get('equipment', '').lower()
                level = exercise.get('level', '').lower()

                # If fatigued, prefer bodyweight and beginner
                if inferred_state in ['fatigued', 'very_tired']:
                    if equipment == 'body only':
                        recovery_score += 0.3
                    if level == 'beginner':
                        recovery_score += 0.2
                # If normal, prefer intermediate/expert
                else:
                    if level in ['intermediate', 'expert']:
                        recovery_score += 0.3

                recovery_score = min(1.0, recovery_score)

            # Weighted composite score
            final_score = (
                freshness * 0.4 +
                preference * 0.4 +
                recovery_score * 0.2
            )

            scored_exercises.append((exercise, final_score))

        # Sort by score (highest first)
        scored_exercises.sort(key=lambda x: x[1], reverse=True)

        return scored_exercises

    def select_exercises(
        self,
        user_id: str,
        guidance: str,
        equipment_available: Optional[List[str]] = None,
        user_state: Optional[Dict[str, Any]] = None,
        count: int = 3
    ) -> List[Dict[str, Any]]:
        """
        Select top N exercises based on Dad's guidance

        Args:
            user_id: User UUID
            guidance: Dad's guidance ("triceps", "upper body", etc.)
            equipment_available: Available equipment
            user_state: Current recovery state from DadOSEngine
            count: Number of exercises to select

        Returns:
            List of top-ranked exercises with scores
        """
        # 1. Get candidate exercises
        candidates = self.get_exercises_for_guidance(
            guidance=guidance,
            equipment_available=equipment_available,
            limit=50
        )

        if not candidates:
            return []

        # 2. Determine primary muscle group for preference lookup
        muscle_groups = self.map_guidance_to_muscles(guidance)
        primary_muscle = muscle_groups[0] if muscle_groups else guidance

        # 3. Rank exercises
        ranked = self.rank_exercises(
            user_id=user_id,
            exercises=candidates,
            muscle_group=primary_muscle,
            user_state=user_state
        )

        # 4. Select top N
        top_exercises = []
        for exercise, score in ranked[:count]:
            exercise_with_score = exercise.copy()
            exercise_with_score['selection_score'] = round(score, 3)
            top_exercises.append(exercise_with_score)

        return top_exercises

    def update_preference_from_feedback(
        self,
        user_id: str,
        muscle_group: str,
        exercise_id: str,
        exercise_name: str,
        quality_rating: int,  # 1-5
        was_override: bool = False
    ):
        """
        Update user's preference score based on feedback

        Args:
            user_id: User UUID
            muscle_group: Target muscle group
            exercise_id: Exercise ID
            exercise_name: Exercise name
            quality_rating: User's quality rating (1-5)
            was_override: Did user choose different exercise?
        """
        # Get existing preference or create new
        result = self.supabase.table('user_exercise_preferences') \
            .select('*') \
            .eq('user_id', user_id) \
            .eq('muscle_group', muscle_group) \
            .eq('exercise_id', exercise_id) \
            .execute()

        if result.data:
            pref = result.data[0]

            # Update existing preference
            times_chosen = pref['times_chosen'] + (0 if was_override else 1)
            times_recommended = pref['times_recommended'] + 1

            # Weighted average of quality ratings
            existing_avg = pref.get('avg_quality_rating', 3)
            existing_count = pref.get('times_chosen', 0)
            new_avg = ((existing_avg * existing_count) + quality_rating) / (existing_count + 1)

            # Calculate new preference score
            # Formula: (quality/5 * 0.7) + (follow_rate * 0.3)
            follow_rate = times_chosen / times_recommended if times_recommended > 0 else 0.5
            new_score = (new_avg / 5 * 0.7) + (follow_rate * 0.3)

            self.supabase.table('user_exercise_preferences') \
                .update({
                    'preference_score': new_score,
                    'times_chosen': times_chosen,
                    'times_recommended': times_recommended,
                    'avg_quality_rating': new_avg,
                    'updated_at': datetime.now().isoformat()
                }) \
                .eq('id', pref['id']) \
                .execute()

        else:
            # Create new preference
            initial_score = (quality_rating / 5 * 0.7) + (0 if was_override else 0.3)

            self.supabase.table('user_exercise_preferences').insert({
                'user_id': user_id,
                'muscle_group': muscle_group,
                'exercise_id': exercise_id,
                'exercise_name': exercise_name,
                'preference_score': initial_score,
                'times_chosen': 0 if was_override else 1,
                'times_recommended': 1,
                'avg_quality_rating': quality_rating,
                'last_performed': datetime.now().date().isoformat()
            }).execute()


# Example usage
if __name__ == "__main__":
    """
    Test the selector with sample data
    """
    selector = ExerciseSelector()

    print("=" * 70)
    print("EXAMPLE: Select tricep exercises")
    print("=" * 70)

    # Example: User wants tricep exercises
    test_user_id = "00000000-0000-0000-0000-000000000000"

    try:
        exercises = selector.select_exercises(
            user_id=test_user_id,
            guidance="triceps",
            equipment_available=["dumbbell", "body only"],
            count=5
        )

        print(f"\n📋 Top 5 Tricep Exercises:")
        for i, ex in enumerate(exercises, 1):
            print(f"\n{i}. {ex['name']}")
            print(f"   Equipment: {ex['equipment']}")
            print(f"   Level: {ex['level']}")
            print(f"   Score: {ex['selection_score']}")
            print(f"   Primary Muscles: {ex['primary_muscles']}")

    except Exception as e:
        print(f"❌ Error (expected if no exercises table): {e}")

    print("\n" + "=" * 70)
    print("EXAMPLE: Map guidance to muscles")
    print("=" * 70)

    test_cases = [
        "triceps",
        "upper body",
        "squats",
        "stretching",
        "back"
    ]

    for guidance in test_cases:
        muscles = selector.map_guidance_to_muscles(guidance)
        print(f"{guidance:20} → {muscles}")
