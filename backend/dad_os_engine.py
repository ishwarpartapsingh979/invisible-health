#!/usr/bin/env python3
"""
Dad OS Rule Matching Engine
============================
Evaluates Dad's 14 rules against user's current state and returns
action vetoes and forces to guide workout selection.

Core Functions:
1. build_user_context() - Assembles state from biometrics, self-report, history
2. match_rules() - Finds all triggered rules
3. calculate_baseline_deviations() - HRV/RHR deviation from 30-day baseline

Used by: agent_engine.py get_workout_recommendation()
"""

import os
import json
from datetime import datetime, timedelta
from typing import Dict, List, Any, Optional, Tuple
from supabase import create_client, Client

class DadOSEngine:
    """
    Rule matching engine for Dad's veteran guidance
    """

    def __init__(self, supabase: Optional[Client] = None):
        """
        Initialize engine with Supabase client

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

    def calculate_baseline_deviations(
        self,
        user_id: str,
        current_hrv: Optional[float] = None,
        current_rhr: Optional[float] = None
    ) -> Dict[str, Any]:
        """
        Calculate HRV/RHR deviations from 30-day rolling baseline

        Args:
            user_id: User UUID
            current_hrv: Today's HRV reading (optional)
            current_rhr: Today's RHR reading (optional)

        Returns:
            {
                'baseline_hrv': float,
                'baseline_rhr': float,
                'hrv_deviation_pct': float,  # -20% means 20% below baseline
                'rhr_deviation_pct': float,  # +10% means 10% above baseline
                'inferred_state': 'normal' | 'fatigued' | 'very_tired'
            }
        """
        # Get last 30 days of biometric data
        thirty_days_ago = (datetime.now() - timedelta(days=30)).isoformat()

        result = self.supabase.table('user_biometrics') \
            .select('hrv, rhr, recorded_at') \
            .eq('user_id', user_id) \
            .gte('recorded_at', thirty_days_ago) \
            .order('recorded_at', desc=True) \
            .execute()

        biometrics = result.data

        if not biometrics:
            return {
                'baseline_hrv': None,
                'baseline_rhr': None,
                'hrv_deviation_pct': 0,
                'rhr_deviation_pct': 0,
                'inferred_state': 'normal'
            }

        # Calculate baselines (30-day average)
        hrv_values = [b['hrv'] for b in biometrics if b.get('hrv')]
        rhr_values = [b['rhr'] for b in biometrics if b.get('rhr')]

        baseline_hrv = sum(hrv_values) / len(hrv_values) if hrv_values else None
        baseline_rhr = sum(rhr_values) / len(rhr_values) if rhr_values else None

        # Calculate deviations
        hrv_deviation_pct = 0
        rhr_deviation_pct = 0

        if current_hrv and baseline_hrv:
            hrv_deviation_pct = ((current_hrv - baseline_hrv) / baseline_hrv) * 100

        if current_rhr and baseline_rhr:
            rhr_deviation_pct = ((current_rhr - baseline_rhr) / baseline_rhr) * 100

        # Infer physical state
        # HRV < -20% OR RHR > +10% = very tired
        # HRV < -10% OR RHR > +5% = fatigued
        inferred_state = 'normal'
        if hrv_deviation_pct < -20 or rhr_deviation_pct > 10:
            inferred_state = 'very_tired'
        elif hrv_deviation_pct < -10 or rhr_deviation_pct > 5:
            inferred_state = 'fatigued'

        return {
            'baseline_hrv': baseline_hrv,
            'baseline_rhr': baseline_rhr,
            'current_hrv': current_hrv,
            'current_rhr': current_rhr,
            'hrv_deviation_pct': round(hrv_deviation_pct, 1),
            'rhr_deviation_pct': round(rhr_deviation_pct, 1),
            'inferred_state': inferred_state
        }

    def get_recent_workout_history(
        self,
        user_id: str,
        days: int = 7
    ) -> List[Dict[str, Any]]:
        """
        Get user's recent workout history

        Args:
            user_id: User UUID
            days: Number of days to look back

        Returns:
            List of workout records with exercises performed
        """
        cutoff_date = (datetime.now() - timedelta(days=days)).date().isoformat()

        result = self.supabase.table('user_exercise_history') \
            .select('*') \
            .eq('user_id', user_id) \
            .gte('workout_date', cutoff_date) \
            .order('workout_date', desc=True) \
            .execute()

        return result.data

    def build_user_context(
        self,
        user_id: str,
        self_report: Optional[Dict[str, Any]] = None,
        current_hrv: Optional[float] = None,
        current_rhr: Optional[float] = None
    ) -> Dict[str, Any]:
        """
        Build complete context for rule matching

        Args:
            user_id: User UUID
            self_report: {
                'energy_level': 1-5,
                'pain_location': str,
                'pain_severity': 0-10,
                'subjective_feeling': str
            }
            current_hrv: Today's HRV
            current_rhr: Today's RHR

        Returns:
            Complete context dictionary for rule evaluation
        """
        # 1. Baseline deviations
        deviations = self.calculate_baseline_deviations(user_id, current_hrv, current_rhr)

        # 2. Recent workout history
        history = self.get_recent_workout_history(user_id, days=7)

        # 3. Yesterday's workout
        yesterday_workout = None
        if history:
            yesterday_date = (datetime.now() - timedelta(days=1)).date().isoformat()
            yesterday_workout = [w for w in history if w['workout_date'] == yesterday_date]

        # 4. Workout streak
        consecutive_days = 0
        if history:
            workout_dates = sorted(set([w['workout_date'] for w in history]))
            # Count consecutive days from today backwards
            check_date = datetime.now().date()
            for _ in range(30):  # Check up to 30 days back
                if check_date.isoformat() in workout_dates:
                    consecutive_days += 1
                    check_date -= timedelta(days=1)
                else:
                    break

        # 5. Extract recent activity type
        previous_day_activity = None
        if yesterday_workout:
            # Get most common guidance from yesterday
            guidance_list = [w.get('dad_guidance') for w in yesterday_workout if w.get('dad_guidance')]
            if guidance_list:
                previous_day_activity = max(set(guidance_list), key=guidance_list.count)

        # Build complete context
        context = {
            # Biometric state
            'hrv_deviation_pct': deviations['hrv_deviation_pct'],
            'rhr_deviation_pct': deviations['rhr_deviation_pct'],
            'inferred_physical_state': deviations['inferred_state'],

            # Self-reported state (from self_report dict)
            'energy_level': self_report.get('energy_level') if self_report else None,
            'pain_location': self_report.get('pain_location') if self_report else None,
            'pain_severity': self_report.get('pain_severity') if self_report else None,
            'subjective_feeling': self_report.get('subjective_feeling') if self_report else None,

            # Workout history
            'consecutive_workout_days': consecutive_days,
            'previous_day_activity': previous_day_activity,
            'recent_workouts': history[:3],  # Last 3 workouts

            # Temporal
            'timestamp': datetime.now().isoformat()
        }

        # Merge physical state from self-report if provided
        if self_report and self_report.get('physical_state'):
            context['physical_state'] = self_report['physical_state']
        elif deviations['inferred_state'] != 'normal':
            context['physical_state'] = deviations['inferred_state']

        return context

    def check_trigger_match(
        self,
        trigger_conditions: Dict[str, Any],
        context: Dict[str, Any]
    ) -> bool:
        """
        Check if rule's trigger conditions match current context

        Args:
            trigger_conditions: Rule's trigger dict (from dad_os_rules.trigger_conditions)
            context: Current user context

        Returns:
            True if ALL trigger conditions match
        """
        for key, expected_value in trigger_conditions.items():
            context_value = context.get(key)

            # Handle different value types
            if isinstance(expected_value, list):
                # Match if context value is in list
                if context_value not in expected_value:
                    return False

            elif isinstance(expected_value, str):
                # String match (case-insensitive partial match)
                if not context_value:
                    return False
                if expected_value.lower() not in str(context_value).lower():
                    return False

            elif isinstance(expected_value, (int, float)):
                # Numeric exact match
                if context_value != expected_value:
                    return False

            else:
                # Generic equality
                if context_value != expected_value:
                    return False

        return True

    def match_rules(
        self,
        user_id: str,
        self_report: Optional[Dict[str, Any]] = None,
        current_hrv: Optional[float] = None,
        current_rhr: Optional[float] = None
    ) -> Tuple[List[Dict[str, Any]], Dict[str, Any]]:
        """
        Match Dad's rules against user's current state

        Args:
            user_id: User UUID
            self_report: Self-reported state (energy, pain, feeling)
            current_hrv: Today's HRV
            current_rhr: Today's RHR

        Returns:
            Tuple of (matched_rules, context)
            - matched_rules: List of dicts with rule_id, action_vetoes, action_forces, rationale
            - context: Full context used for matching (for logging)
        """
        # Build context
        context = self.build_user_context(user_id, self_report, current_hrv, current_rhr)

        # Get all active rules
        result = self.supabase.table('dad_os_rules') \
            .select('*') \
            .eq('hitl_status', 'Active') \
            .execute()

        all_rules = result.data

        # Match rules
        matched_rules = []

        for rule in all_rules:
            trigger_conditions = rule.get('trigger_conditions', {})

            # Check if triggers match
            if self.check_trigger_match(trigger_conditions, context):
                matched_rules.append({
                    'rule_id': rule['id'],
                    'action_vetoes': rule.get('action_vetoes', []),
                    'action_forces': rule.get('action_forces', []),
                    'veteran_rationale': rule.get('veteran_rationale', ''),
                    'trigger_conditions': trigger_conditions
                })

        return matched_rules, context

    def log_rule_firing(
        self,
        user_id: str,
        rule_id: str,
        trigger_context: Dict[str, Any],
        user_action: str,  # 'followed', 'overrode', 'modified'
        override_reason: Optional[str] = None,
        conversation_transcript: Optional[str] = None
    ):
        """
        Log when a rule fires (for analytics and learning)

        Args:
            user_id: User UUID
            rule_id: Rule UUID that fired
            trigger_context: Full context when rule fired
            user_action: 'followed', 'overrode', 'modified'
            override_reason: Why user overrode (if applicable)
            conversation_transcript: Gemini conversation (if available)
        """
        self.supabase.table('rule_firing_events').insert({
            'user_id': user_id,
            'rule_id': rule_id,
            'trigger_context': trigger_context,
            'user_action': user_action,
            'override_reason': override_reason,
            'conversation_transcript': conversation_transcript,
            'fired_at': datetime.now().isoformat()
        }).execute()

    def get_rule_effectiveness(self, rule_id: str) -> Dict[str, Any]:
        """
        Calculate rule's historical effectiveness

        Args:
            rule_id: Rule UUID

        Returns:
            {
                'total_firings': int,
                'followed_count': int,
                'overrode_count': int,
                'follow_rate': float (0-1),
                'was_helpful_rate': float (0-1)
            }
        """
        result = self.supabase.table('rule_firing_events') \
            .select('*') \
            .eq('rule_id', rule_id) \
            .execute()

        events = result.data

        if not events:
            return {
                'total_firings': 0,
                'followed_count': 0,
                'overrode_count': 0,
                'follow_rate': 0,
                'was_helpful_rate': 0
            }

        total = len(events)
        followed = len([e for e in events if e.get('user_action') == 'followed'])
        overrode = len([e for e in events if e.get('user_action') == 'overrode'])
        helpful = len([e for e in events if e.get('rule_was_helpful') is True])

        return {
            'total_firings': total,
            'followed_count': followed,
            'overrode_count': overrode,
            'follow_rate': followed / total if total > 0 else 0,
            'was_helpful_rate': helpful / total if total > 0 else 0
        }


# Example usage
if __name__ == "__main__":
    """
    Test the engine with sample data
    """
    engine = DadOSEngine()

    # Example 1: Very tired user after recent strides
    print("=" * 70)
    print("EXAMPLE 1: Very tired after strides")
    print("=" * 70)

    sample_context = {
        'energy_level': 2,  # Low energy (1-5 scale)
        'physical_state': 'tired after recent strides',
        'subjective_feeling': 'in the rhythm'
    }

    # Simulate with test user (replace with real UUID)
    test_user_id = "00000000-0000-0000-0000-000000000000"

    try:
        matched_rules, context = engine.match_rules(
            user_id=test_user_id,
            self_report=sample_context,
            current_hrv=35,  # Low HRV
            current_rhr=75   # Elevated RHR
        )

        print(f"\n📋 Context Built:")
        print(json.dumps(context, indent=2))

        print(f"\n🎯 Matched Rules: {len(matched_rules)}")
        for rule in matched_rules:
            print(f"\n  Rule ID: {rule['rule_id']}")
            print(f"  ❌ Vetoes: {rule['action_vetoes']}")
            print(f"  ✅ Forces: {rule['action_forces']}")
            print(f"  💡 Rationale: {rule['veteran_rationale']}")

    except Exception as e:
        print(f"❌ Error (expected if no test user): {e}")
