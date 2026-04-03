#!/usr/bin/env python3
"""
Gemini Flash Live - Voice Conversation Handler
==============================================
Real-time audio-audio conversation with Dad's personality.

Features:
1. Morning check-in: "How do you feel today?"
2. Self-report collection (energy, pain, feeling)
3. Rule matching + exercise selection
4. Exercise explanation with form cues
5. Workout logging

Uses: Gemini 2.0 Flash with multimodal input/output
"""

import os
import json
import uuid
from datetime import datetime
from typing import Dict, List, Any, Optional
import vertexai
from vertexai.generative_models import GenerativeModel, Part
from supabase import create_client, Client

from dad_os_engine import DadOSEngine
from exercise_selector import ExerciseSelector


class GeminiFlashLive:
    """
    Voice conversation handler with Dad's personality
    """

    def __init__(self, supabase: Optional[Client] = None):
        """
        Initialize Gemini Flash Live with Dad OS integration

        Args:
            supabase: Optional Supabase client
        """
        # Supabase setup
        if supabase:
            self.supabase = supabase
        else:
            url = os.environ.get("SUPABASE_URL")
            key = os.environ.get("SUPABASE_SERVICE_KEY")
            if not url or not key:
                raise ValueError("Missing Supabase credentials")
            self.supabase = create_client(url, key)

        # Initialize Gemini (using gemini-2.0-flash-exp for audio)
        vertexai.init()
        self.model = GenerativeModel("gemini-2.0-flash-exp")

        # Initialize Dad OS components
        self.dad_engine = DadOSEngine(supabase=self.supabase)
        self.exercise_selector = ExerciseSelector(supabase=self.supabase)

        print("✅ Gemini Flash Live initialized")

    def get_dad_system_prompt(self, user_context: Optional[Dict[str, Any]] = None) -> str:
        """
        Generate Dad's system prompt with rules and personality

        Args:
            user_context: Optional context (matched rules, exercises, etc.)

        Returns:
            System prompt string
        """
        base_personality = """
You are DAD - a veteran fitness coach with 30+ years of experience preventing injuries.
Your voice is warm, direct, and authoritative. You care deeply about keeping athletes healthy.

YOUR PERSONALITY:
- Speak like a wise father figure (warm but firm)
- Use analogies and real-world examples
- Never sugarcoat - tell the truth even if it's hard to hear
- Celebrate discipline, call out poor choices directly
- Keep responses SHORT (20-30 seconds max)
- Use conversational language: "Listen kid...", "Here's the deal...", "Look..."

YOUR CORE RULES (14 VETERAN PRINCIPLES):
These rules are based on 30 years of preventing injuries. They override everything else.

1. HEAVY WEIGHTS + UPPER ABS = INJURY
   - Veto: weighted exercises >5kg for upper abs
   - Force: medicine ball 2-5kg, lower back on ground
   - Why: Heavy weights for upper abs cause back injuries. Lighter is safer and more effective.

2. STRIDES DAY → MINIMAL LEGS NEXT DAY
   - Veto: weighted leg exercises, high-intensity leg work
   - Force: bodyweight squats, minimal leg exercises
   - Why: Strides tax legs heavily. Next day needs recovery even if upper body is the focus.

3. TIRED AFTER STRIDES → REPEAT SAME WORKOUT
   - Context: Tired 2-3 days after strides
   - Veto: increase stride count/effort
   - Force: repeat previous stride workout
   - Why: Body hasn't adapted yet. Increasing load = overtraining risk.

4. KNEE/HAMSTRING PAIN → REDUCE IMPACT
   - Context: Minor knee or hamstring pain
   - Veto: jogging, high-impact lower body
   - Force: brisk walking, light strides, upper body
   - Why: Test the injury with reduced impact. Shift focus to maintain consistency.

5. POST-WORKOUT → COMPLETE THE SESSION
   - Context: Primary activity (strides/run) done
   - Force: abs, upper body, stretching
   - Why: Running alone isn't a complete session. Add core, strength, flexibility.

6. OBESE → LOW-IMPACT CARDIO
   - Context: Obese condition
   - Force: cycling, half-court basketball
   - Why: Protect knees from high-impact stress.

7. BAD WEATHER → INDOOR TRAINING
   - Context: Hot, cold, or raining
   - Veto: outdoor training
   - Force: gym training
   - Why: Adverse weather makes outdoor training unsafe and ineffective.

8. VERY TIRED + <5 MIN AVAILABLE → LIGHT MOVEMENT
   - Context: High fatigue, only 5 minutes
   - Force: light arm rotation, stretching
   - Why: Maintains habit. Often leads to longer workout once you start.

9. MUSCLE SORENESS → ACTIVE RECOVERY
   - Context: Muscle soreness from previous day
   - Veto: full-blown workout, gym
   - Force: long walk 30-45min, abs, squats, push-ups
   - Why: Active recovery aids healing. Avoid high-intensity when sore.

10. VERY TIRED → NO GYM
    - Context: Very tired physical state
    - Veto: gym workout
    - Why: Fatigue increases injury risk. Rest is training.

11. 10-15 DAYS SOLO WORKOUTS → ADD SPORTS
    - Context: 10-15 consecutive days of individual workouts, boredom
    - Force: tennis, volleyball, basketball, football, team sports
    - Why: Variety prevents burnout. Social element maintains motivation.

12. LOW ENGAGEMENT/BORED → VARIETY
    - Context: Low engagement, bored
    - Veto: routine workout
    - Force: workout variation, environmental change, group activities, 3x/week strength minimum
    - Why: Surprise and variety bring motivation back.

13. DISLIKES LOW BODY POSITION → UPPER BODY FOCUS
    - Context: Psychological dislike of low body positions
    - Veto: lower body exercises
    - Force: upper body exercises
    - Why: Negative mindset → poor form → injury. Better to focus where mindset is positive.

14. LONG DAY + >10 MIN AVAILABLE → SIMPLE BODYWEIGHT
    - Context: Long day, mentally tired, >10 minutes
    - Veto: equipment-based exercises
    - Force: bodyweight exercises, abs, stretching, push-ups
    - Why: Simple workout is achievable when energy is low. Consistency over intensity.

15. HIGH INTENSITY LEGS/SHOULDERS → EXTENDED REST
    - Context: Previous workout was high intensity (legs or shoulders)
    - Force: extended rest, extended sleep
    - Why: Major muscle groups need significant recovery time.

YOUR CONVERSATION STYLE:
- Ask ONE question at a time
- Listen carefully to responses
- Reference specific biometrics when making decisions
- Explain the "why" briefly (1 sentence)
- End with clear next step

AUDIO RESPONSE RULES:
- Keep responses under 30 seconds
- Use natural speech patterns (pauses, emphasis)
- Speak at moderate pace (not rushed)
- Use warm, encouraging tone even when being firm
"""

        # Add context-specific guidance if provided
        context_section = ""
        if user_context:
            if user_context.get('matched_rules'):
                rules = user_context['matched_rules']
                context_section += f"\n\nCURRENT SESSION CONTEXT:\n"
                context_section += f"- {len(rules)} rule(s) triggered for this athlete today\n"

                vetoes = []
                forces = []
                for rule in rules:
                    vetoes.extend(rule.get('action_vetoes', []))
                    forces.extend(rule.get('action_forces', []))

                if vetoes:
                    context_section += f"- VETOES: {', '.join(vetoes)}\n"
                if forces:
                    context_section += f"- FORCES: {', '.join(forces)}\n"

            if user_context.get('selected_exercises'):
                exercises = user_context['selected_exercises']
                context_section += f"\n- Selected exercises: {', '.join([e['name'] for e in exercises])}\n"

        return base_personality + context_section

    def start_conversation(
        self,
        user_id: str,
        conversation_type: str = "morning_checkin"
    ) -> Dict[str, Any]:
        """
        Start a new conversation session

        Args:
            user_id: User UUID
            conversation_type: Type of conversation (morning_checkin, manual_workout_logging, etc.)

        Returns:
            {
                'session_id': str,
                'greeting': str (text version for UI),
                'audio_url': str (future: generated audio)
            }
        """
        session_id = str(uuid.uuid4())

        # Create conversation record
        self.supabase.table('gemini_conversations').insert({
            'user_id': user_id,
            'session_id': session_id,
            'conversation_history': [],
            'started_at': datetime.now().isoformat()
        }).execute()

        # Generate greeting based on conversation type
        if conversation_type == "morning_checkin":
            greeting = "Good morning! Let's figure out what your body needs today. On a scale of 1 to 5, how's your energy level? 1 being exhausted, 5 being ready to crush it."
            next_step = 'energy_level'
        elif conversation_type == "manual_workout_logging":
            greeting = "Hey! Tell me what you did today. What exercises, how many sets and reps?"
            next_step = 'parse_workout'
        elif conversation_type == "workout_annotation":
            greeting = "Hey! Which workout do you want to tell me about?"
            next_step = 'identify_workout'
        else:
            greeting = "Hey there! What can I help you with today?"
            next_step = 'general'

        return {
            'session_id': session_id,
            'greeting': greeting,
            'next_step': next_step
        }

    def process_voice_input(
        self,
        session_id: str,
        user_id: str,
        audio_data: Optional[bytes] = None,
        text_input: Optional[str] = None,
        current_step: str = "energy_level"
    ) -> Dict[str, Any]:
        """
        Process user's voice input and generate Dad's response

        Args:
            session_id: Conversation session ID
            user_id: User UUID
            audio_data: Audio bytes (future implementation)
            text_input: Text input (for now, until audio streaming works)
            current_step: Current step in conversation flow

        Returns:
            {
                'response_text': str,
                'next_step': str,
                'self_report': dict (accumulated data),
                'exercises': list (if ready)
            }
        """
        # Get conversation history
        conv_result = self.supabase.table('gemini_conversations') \
            .select('*') \
            .eq('session_id', session_id) \
            .execute()

        if not conv_result.data:
            return {'error': 'Session not found'}

        conversation = conv_result.data[0]
        history = conversation.get('conversation_history', [])

        # Add user input to history
        user_message = {
            'role': 'user',
            'message': text_input or '[audio]',
            'timestamp': datetime.now().isoformat(),
            'step': current_step
        }
        history.append(user_message)

        # Parse input based on current step
        self_report = self._extract_self_report_from_history(history)

        # Determine next step and generate response
        response_text = ""
        next_step = ""
        exercises = None

        if current_step == "energy_level":
            # Parse energy level (1-5)
            energy = self._parse_energy_level(text_input)
            self_report['energy_level'] = energy

            # Ask about pain
            if energy <= 2:
                response_text = "Got it - energy is low today. Any pain or soreness? Tell me where and how bad it is."
                next_step = "pain_check"
            else:
                response_text = "Good energy today. Any pain or soreness I should know about?"
                next_step = "pain_check"

        elif current_step == "pain_check":
            # Parse pain location and severity
            pain_info = self._parse_pain_info(text_input)
            if pain_info:
                self_report.update(pain_info)

            # Ask about subjective feeling
            response_text = "Okay. How are you feeling overall? In the rhythm, dragging, somewhere in between?"
            next_step = "subjective_feeling"

        elif current_step == "subjective_feeling":
            # Parse subjective feeling
            self_report['subjective_feeling'] = text_input

            # Now we have enough info - match rules and select exercises
            matched_rules, dad_context = self.dad_engine.match_rules(
                user_id=user_id,
                self_report=self_report,
                current_hrv=self_report.get('hrv'),
                current_rhr=self_report.get('rhr')
            )

            # Determine guidance from matched rules
            guidance = self._determine_guidance_from_rules(matched_rules, dad_context)

            # Select exercises
            exercises = self.exercise_selector.select_exercises(
                user_id=user_id,
                guidance=guidance,
                equipment_available=["body only", "dumbbell", "barbell"],
                user_state=dad_context,
                count=3
            )

            # Generate Dad's prescription
            response_text = self._generate_workout_prescription(
                matched_rules=matched_rules,
                exercises=exercises,
                self_report=self_report
            )

            next_step = "workout_ready"

        # Add Dad's response to history
        dad_message = {
            'role': 'assistant',
            'message': response_text,
            'timestamp': datetime.now().isoformat(),
            'step': current_step,
            'self_report': self_report
        }
        history.append(dad_message)

        # Update conversation in database
        self.supabase.table('gemini_conversations') \
            .update({
                'conversation_history': history,
                'updated_at': datetime.now().isoformat()
            }) \
            .eq('session_id', session_id) \
            .execute()

        return {
            'response_text': response_text,
            'next_step': next_step,
            'self_report': self_report,
            'exercises': exercises,
            'session_id': session_id
        }

    def _extract_self_report_from_history(self, history: List[Dict]) -> Dict[str, Any]:
        """Extract accumulated self-report data from conversation history"""
        self_report = {}
        for msg in history:
            if msg.get('self_report'):
                self_report.update(msg['self_report'])
        return self_report

    def _parse_energy_level(self, text: str) -> int:
        """Parse energy level from user input (1-5)"""
        text_lower = text.lower()

        # Direct number matching
        for num in range(1, 6):
            if str(num) in text:
                return num

        # Keyword matching
        if any(word in text_lower for word in ['exhausted', 'terrible', 'awful']):
            return 1
        elif any(word in text_lower for word in ['tired', 'low', 'drained']):
            return 2
        elif any(word in text_lower for word in ['okay', 'alright', 'moderate']):
            return 3
        elif any(word in text_lower for word in ['good', 'ready', 'solid']):
            return 4
        elif any(word in text_lower for word in ['great', 'crush', 'excellent', 'amazing']):
            return 5

        return 3  # Default moderate

    def _parse_pain_info(self, text: str) -> Optional[Dict[str, Any]]:
        """Parse pain location and severity from user input"""
        text_lower = text.lower()

        # Check for "no pain"
        if any(phrase in text_lower for phrase in ['no pain', 'no soreness', 'none', 'feeling good']):
            return None

        pain_info = {}

        # Location
        if 'knee' in text_lower:
            pain_info['pain_location'] = 'knee'
        elif 'hamstring' in text_lower:
            pain_info['pain_location'] = 'hamstring'
        elif 'back' in text_lower:
            pain_info['pain_location'] = 'back'
        elif 'shoulder' in text_lower:
            pain_info['pain_location'] = 'shoulder'

        # Severity (0-10)
        if any(word in text_lower for word in ['minor', 'slight', 'little']):
            pain_info['pain_severity'] = 3
        elif any(word in text_lower for word in ['moderate', 'medium']):
            pain_info['pain_severity'] = 5
        elif any(word in text_lower for word in ['bad', 'severe', 'really']):
            pain_info['pain_severity'] = 8
        else:
            pain_info['pain_severity'] = 5  # Default moderate

        return pain_info if pain_info else None

    def _determine_guidance_from_rules(
        self,
        matched_rules: List[Dict[str, Any]],
        context: Dict[str, Any]
    ) -> str:
        """
        Determine workout guidance from matched rules and context

        Args:
            matched_rules: List of triggered rules
            context: User context from DadOSEngine

        Returns:
            Guidance string (e.g., "triceps", "upper body", "stretching")
        """
        # Extract forces from matched rules
        forces = []
        for rule in matched_rules:
            forces.extend(rule.get('action_forces', []))

        # If rules force specific exercises, use that
        if forces:
            # Pick first force as primary guidance
            primary_force = forces[0].lower()

            # Map force to guidance
            if 'tricep' in primary_force:
                return 'triceps'
            elif 'upper body' in primary_force:
                return 'upper body'
            elif 'stretch' in primary_force:
                return 'stretching'
            elif 'abs' in primary_force or 'core' in primary_force:
                return 'abs'
            elif 'squat' in primary_force:
                return 'squats'
            elif 'push' in primary_force:
                return 'push-ups'
            else:
                return primary_force

        # Otherwise, use intelligent defaults based on context
        energy_level = context.get('energy_level', 3)
        physical_state = context.get('inferred_physical_state', 'normal')

        if physical_state == 'very_tired' or energy_level <= 2:
            return 'stretching'
        elif energy_level >= 4:
            return 'upper body'
        else:
            return 'abs'

    def _generate_workout_prescription(
        self,
        matched_rules: List[Dict[str, Any]],
        exercises: List[Dict[str, Any]],
        self_report: Dict[str, Any]
    ) -> str:
        """
        Generate Dad's workout prescription in his voice

        Args:
            matched_rules: Triggered rules
            exercises: Selected exercises
            self_report: User's self-report data

        Returns:
            Dad's prescription text
        """
        energy = self_report.get('energy_level', 3)

        # Build prescription
        if energy <= 2:
            opening = "Listen kid, your body's telling me it needs recovery today."
        elif energy >= 4:
            opening = "Alright, you've got good energy today. Let's put it to work."
        else:
            opening = "Here's the deal - you're not firing on all cylinders, but you're not dead either."

        # Explain the why (from rules)
        rationale = ""
        if matched_rules:
            rule = matched_rules[0]  # Use first rule's rationale
            rationale = f" {rule['veteran_rationale']}"

        # List exercises
        exercise_list = ""
        if exercises:
            exercise_names = [ex['name'] for ex in exercises[:3]]
            exercise_list = f"\n\nHere's what we're doing:\n" + "\n".join([f"{i+1}. {name}" for i, name in enumerate(exercise_names)])
            exercise_list += "\n\nI'll walk you through each one with proper form. Let's start with the first exercise."

        return opening + rationale + exercise_list

    def explain_exercise(
        self,
        exercise: Dict[str, Any],
        user_context: Optional[Dict[str, Any]] = None
    ) -> str:
        """
        Generate Dad's explanation of an exercise with form cues

        Args:
            exercise: Exercise dict from exercises table
            user_context: Optional user context (energy level, pain, etc.)

        Returns:
            Dad's explanation text
        """
        name = exercise.get('name', 'this exercise')
        instructions = exercise.get('instructions', [])
        equipment = exercise.get('equipment', 'body only')
        level = exercise.get('level', 'beginner')

        # Build explanation
        intro = f"Okay, {name}. "

        # Equipment setup
        if equipment != 'body only':
            intro += f"You'll need {equipment}. "

        # Form cues (use instructions from exercise)
        form_cues = ""
        if instructions:
            form_cues = "Here's how: " + " ".join(instructions[:3])  # First 3 steps

        # Dad's emphasis
        emphasis = ""
        if 'squat' in name.lower():
            emphasis = " Keep your knees behind your toes and chest up. That's non-negotiable."
        elif 'push' in name.lower():
            emphasis = " Elbows at 45 degrees, not flared out. Protect those shoulders."
        elif 'pull' in name.lower():
            emphasis = " Squeeze your shoulder blades together at the top. That's where the magic happens."

        # Adjust for user state
        modification = ""
        if user_context:
            energy = user_context.get('energy_level', 3)
            if energy <= 2:
                modification = " Since you're low on energy today, take it slow. Quality over speed."

        return intro + form_cues + emphasis + modification

    def parse_workout_from_text(self, text: str) -> List[Dict[str, Any]]:
        """
        Parse workout from natural language using Gemini

        Args:
            text: User's workout description (e.g., "3 sets of 10 push-ups, 2 sets of 12 squats")

        Returns:
            List of exercises: [
                {
                    'exercise_name': str,
                    'sets': int,
                    'reps': int,
                    'weight_kg': float (optional)
                }
            ]
        """
        prompt = f"""
Parse this workout description into structured data.

User said: "{text}"

Extract all exercises mentioned with their sets, reps, and weight (if mentioned).

Return ONLY valid JSON (no markdown, no explanation) in this format:
{{
  "exercises": [
    {{"exercise_name": "Push-ups", "sets": 3, "reps": 10, "weight_kg": null}},
    {{"exercise_name": "Squats", "sets": 2, "reps": 12, "weight_kg": null}}
  ]
}}

Rules:
- Standardize exercise names (e.g., "pushups" → "Push-ups", "bodyweight squats" → "Squats")
- If no sets/reps mentioned, use null
- Only include weight_kg if explicitly mentioned with kg/lbs
- Convert lbs to kg if needed (1 lb = 0.45 kg)
"""

        try:
            response = self.model.generate_content(prompt)
            parsed_json = json.loads(response.text.strip())
            return parsed_json.get('exercises', [])
        except Exception as e:
            print(f"❌ Error parsing workout: {e}")
            # Fallback: try to extract at least exercise names
            return []

    def log_workout_to_database(
        self,
        user_id: str,
        exercises: List[Dict[str, Any]],
        quality_rating: Optional[int] = None,
        soreness: Optional[int] = None,
        workout_date: Optional[str] = None
    ) -> bool:
        """
        Log workout exercises to user_exercise_history

        Args:
            user_id: User UUID
            exercises: List of exercise dicts from parse_workout_from_text()
            quality_rating: 1-5 rating
            soreness: 0-10 soreness level
            workout_date: Date (defaults to today)

        Returns:
            True if successful
        """
        try:
            if not workout_date:
                workout_date = datetime.now().date().isoformat()

            for exercise in exercises:
                record = {
                    'user_id': user_id,
                    'workout_date': workout_date,
                    'exercise_name': exercise.get('exercise_name'),
                    'sets': exercise.get('sets'),
                    'reps': exercise.get('reps'),
                    'weight_kg': exercise.get('weight_kg'),
                    'quality_rating': quality_rating,
                    'next_day_soreness': soreness,
                    'was_recommended': False,  # Manual entry
                    'was_override': False
                }

                # Remove None values
                record = {k: v for k, v in record.items() if v is not None}

                # Insert into database
                self.supabase.table('user_exercise_history').insert(record).execute()

            print(f"✅ Logged {len(exercises)} exercises to database")
            return True

        except Exception as e:
            print(f"❌ Error logging workout to database: {e}")
            import traceback
            traceback.print_exc()
            return False

    def process_manual_workout_logging(
        self,
        session_id: str,
        user_id: str,
        text_input: str,
        current_step: str
    ) -> Dict[str, Any]:
        """
        Handle manual workout logging conversation flow

        Steps:
        1. parse_workout - Parse exercise description
        2. quality_feedback - Ask how it felt (1-5)
        3. soreness_check - Ask about soreness (0-10)
        4. complete - Log to database

        Args:
            session_id: Conversation session ID
            user_id: User UUID
            text_input: User's input
            current_step: Current step in flow

        Returns:
            {
                'response_text': str,
                'next_step': str,
                'exercises': list (accumulated),
                'logged': bool (if complete)
            }
        """
        # Get conversation history
        conv_result = self.supabase.table('gemini_conversations') \
            .select('*') \
            .eq('session_id', session_id) \
            .execute()

        if not conv_result.data:
            return {'error': 'Session not found'}

        conversation = conv_result.data[0]
        history = conversation.get('conversation_history', [])

        # Add user input to history
        user_message = {
            'role': 'user',
            'message': text_input,
            'timestamp': datetime.now().isoformat(),
            'step': current_step
        }
        history.append(user_message)

        # Extract accumulated data
        accumulated_data = {}
        for msg in history:
            if msg.get('accumulated_data'):
                accumulated_data.update(msg['accumulated_data'])

        response_text = ""
        next_step = ""
        exercises = accumulated_data.get('exercises', [])

        if current_step == "parse_workout":
            # Parse the workout description
            exercises = self.parse_workout_from_text(text_input)

            if not exercises:
                response_text = "Hmm, I didn't catch that. Can you tell me again what exercises you did? Like '3 sets of 10 push-ups'."
                next_step = "parse_workout"
            else:
                accumulated_data['exercises'] = exercises

                # Confirm what we heard
                exercise_summary = ", ".join([
                    f"{ex.get('sets', '?')} sets of {ex.get('reps', '?')} {ex['exercise_name']}"
                    for ex in exercises
                ])
                response_text = f"Got it - {exercise_summary}. How did it feel? Give me a rating from 1 to 5. 1 being terrible, 5 being excellent."
                next_step = "quality_feedback"

        elif current_step == "quality_feedback":
            # Parse quality rating
            quality = self._parse_number_from_text(text_input, 1, 5)

            if quality is None:
                response_text = "Didn't catch that. How did it feel on a scale of 1 to 5?"
                next_step = "quality_feedback"
            else:
                accumulated_data['quality_rating'] = quality
                response_text = "Copy that. Any soreness today? Rate it 0 to 10, where 0 is no soreness and 10 is can't move."
                next_step = "soreness_check"

        elif current_step == "soreness_check":
            # Parse soreness level
            soreness = self._parse_number_from_text(text_input, 0, 10)

            if soreness is None:
                response_text = "Didn't catch that. Soreness level, 0 to 10?"
                next_step = "soreness_check"
            else:
                accumulated_data['soreness'] = soreness

                # Log to database
                success = self.log_workout_to_database(
                    user_id=user_id,
                    exercises=accumulated_data.get('exercises', []),
                    quality_rating=accumulated_data.get('quality_rating'),
                    soreness=soreness
                )

                if success:
                    response_text = "Perfect. Workout logged. Keep crushing it!"
                    next_step = "complete"
                else:
                    response_text = "Had trouble logging that. Let me try again."
                    next_step = "complete"

                accumulated_data['logged'] = success

        # Add Dad's response to history
        dad_message = {
            'role': 'assistant',
            'message': response_text,
            'timestamp': datetime.now().isoformat(),
            'step': current_step,
            'accumulated_data': accumulated_data
        }
        history.append(dad_message)

        # Update conversation in database
        self.supabase.table('gemini_conversations') \
            .update({
                'conversation_history': history,
                'updated_at': datetime.now().isoformat()
            }) \
            .eq('session_id', session_id) \
            .execute()

        return {
            'response_text': response_text,
            'next_step': next_step,
            'exercises': accumulated_data.get('exercises', []),
            'logged': accumulated_data.get('logged', False),
            'session_id': session_id
        }

    def _parse_number_from_text(self, text: str, min_val: int, max_val: int) -> Optional[int]:
        """
        Extract a number from text within a range

        Args:
            text: User input
            min_val: Minimum valid value
            max_val: Maximum valid value

        Returns:
            Extracted number or None
        """
        import re

        # Try to find a number
        numbers = re.findall(r'\d+', text)

        for num_str in numbers:
            num = int(num_str)
            if min_val <= num <= max_val:
                return num

        # Try word matching
        words = text.lower().split()
        word_to_num = {
            'zero': 0, 'one': 1, 'two': 2, 'three': 3, 'four': 4,
            'five': 5, 'six': 6, 'seven': 7, 'eight': 8, 'nine': 9, 'ten': 10
        }

        for word in words:
            if word in word_to_num:
                num = word_to_num[word]
                if min_val <= num <= max_val:
                    return num

        return None

    def find_workout_by_reference(
        self,
        user_id: str,
        reference_text: str
    ) -> Optional[Dict[str, Any]]:
        """
        Find a workout based on temporal or descriptive reference

        Args:
            user_id: User UUID
            reference_text: User's workout reference (e.g., "morning workout", "yesterday's run", "leg day")

        Returns:
            Workout record from apple_watch_workouts table, or None
        """
        from datetime import timedelta

        reference_lower = reference_text.lower()
        now = datetime.now()

        # Define time windows
        time_filters = {}

        # Temporal references
        if 'morning' in reference_lower:
            # Morning: 6am-12pm today
            start_time = now.replace(hour=6, minute=0, second=0, microsecond=0)
            end_time = now.replace(hour=12, minute=0, second=0, microsecond=0)
            time_filters['start'] = start_time
            time_filters['end'] = end_time

        elif 'afternoon' in reference_lower or 'lunch' in reference_lower:
            # Afternoon: 12pm-5pm today
            start_time = now.replace(hour=12, minute=0, second=0, microsecond=0)
            end_time = now.replace(hour=17, minute=0, second=0, microsecond=0)
            time_filters['start'] = start_time
            time_filters['end'] = end_time

        elif 'evening' in reference_lower or 'tonight' in reference_lower:
            # Evening: 5pm-11pm today
            start_time = now.replace(hour=17, minute=0, second=0, microsecond=0)
            end_time = now.replace(hour=23, minute=59, second=59, microsecond=0)
            time_filters['start'] = start_time
            time_filters['end'] = end_time

        elif 'yesterday' in reference_lower:
            # Yesterday: all day
            yesterday = now - timedelta(days=1)
            start_time = yesterday.replace(hour=0, minute=0, second=0, microsecond=0)
            end_time = yesterday.replace(hour=23, minute=59, second=59, microsecond=0)
            time_filters['start'] = start_time
            time_filters['end'] = end_time

        elif 'today' in reference_lower or 'earlier' in reference_lower:
            # Today: all day
            start_time = now.replace(hour=0, minute=0, second=0, microsecond=0)
            end_time = now
            time_filters['start'] = start_time
            time_filters['end'] = end_time

        elif 'last' in reference_lower:
            # Last 7 days
            start_time = now - timedelta(days=7)
            end_time = now
            time_filters['start'] = start_time
            time_filters['end'] = end_time

        else:
            # Default: last 24 hours
            start_time = now - timedelta(hours=24)
            end_time = now
            time_filters['start'] = start_time
            time_filters['end'] = end_time

        # Build query
        query = self.supabase.table('apple_watch_workouts') \
            .select('*') \
            .eq('user_id', user_id) \
            .gte('start_date', time_filters['start'].isoformat()) \
            .lte('start_date', time_filters['end'].isoformat()) \
            .order('start_date', desc=True)

        # Add workout type filter if mentioned
        workout_type_keywords = {
            'run': 'Running',
            'running': 'Running',
            'cycle': 'Cycling',
            'cycling': 'Cycling',
            'bike': 'Cycling',
            'swim': 'Swimming',
            'swimming': 'Swimming',
            'strength': 'Strength Training',
            'lifting': 'Strength Training',
            'weights': 'Strength Training',
            'leg': 'Strength Training',  # Assume strength
            'upper': 'Strength Training'
        }

        for keyword, workout_name in workout_type_keywords.items():
            if keyword in reference_lower:
                query = query.eq('workout_name', workout_name)
                break

        # Execute query
        result = query.execute()

        if result.data:
            # Return the most recent matching workout
            return result.data[0]

        return None

    def process_workout_annotation(
        self,
        session_id: str,
        user_id: str,
        text_input: str,
        current_step: str
    ) -> Dict[str, Any]:
        """
        Handle workout annotation conversation flow

        Steps:
        1. identify_workout - Parse temporal reference and find workout
        2. collect_annotation - User describes what happened
        3. complete - Update workout record with annotation

        Args:
            session_id: Conversation session ID
            user_id: User UUID
            text_input: User's input
            current_step: Current step in flow

        Returns:
            {
                'response_text': str,
                'next_step': str,
                'workout': dict (if found),
                'annotated': bool (if complete)
            }
        """
        # Get conversation history
        conv_result = self.supabase.table('gemini_conversations') \
            .select('*') \
            .eq('session_id', session_id) \
            .execute()

        if not conv_result.data:
            return {'error': 'Session not found'}

        conversation = conv_result.data[0]
        history = conversation.get('conversation_history', [])

        # Add user input to history
        user_message = {
            'role': 'user',
            'message': text_input,
            'timestamp': datetime.now().isoformat(),
            'step': current_step
        }
        history.append(user_message)

        # Extract accumulated data
        accumulated_data = {}
        for msg in history:
            if msg.get('accumulated_data'):
                accumulated_data.update(msg['accumulated_data'])

        response_text = ""
        next_step = ""

        if current_step == "identify_workout":
            # Find the workout based on user's reference
            workout = self.find_workout_by_reference(user_id, text_input)

            if not workout:
                response_text = "Hmm, I can't find a workout matching that description. Can you be more specific? Like 'my morning run' or 'yesterday's workout'?"
                next_step = "identify_workout"
            else:
                accumulated_data['workout'] = workout

                # Confirm which workout we found
                workout_name = workout.get('workout_name', 'workout')
                start_date = workout.get('start_date', '')

                # Parse start_date to friendly format
                try:
                    start_dt = datetime.fromisoformat(start_date.replace('Z', '+00:00'))
                    time_str = start_dt.strftime('%I:%M %p')  # e.g., "08:15 AM"

                    # Check if today or yesterday
                    now = datetime.now()
                    if start_dt.date() == now.date():
                        day_str = "today"
                    elif start_dt.date() == (now - timedelta(days=1)).date():
                        day_str = "yesterday"
                    else:
                        day_str = start_dt.strftime('%A')  # e.g., "Monday"

                    friendly_time = f"{day_str} at {time_str}"
                except:
                    friendly_time = "recently"

                response_text = f"I see you did a {workout_name} session {friendly_time}. What about it?"
                next_step = "collect_annotation"

        elif current_step == "collect_annotation":
            # Parse the annotation using Gemini
            annotation_data = self._parse_annotation_with_ai(text_input)
            accumulated_data['annotation'] = annotation_data

            # Update the workout record
            workout = accumulated_data.get('workout')
            if workout:
                success = self._attach_annotation_to_workout(
                    workout_id=workout['id'],
                    annotation_text=text_input,
                    pain_info=annotation_data.get('pain_info')
                )

                if success:
                    # Acknowledge the annotation
                    if annotation_data.get('pain_info'):
                        pain_location = annotation_data['pain_info'].get('location', 'that area')
                        response_text = f"Got it. Logging that note. Watch the {pain_location} on your next session. Anything else hurt you?"
                    else:
                        response_text = "Noted. I'll keep that in mind for your next workout."

                    next_step = "complete"
                    accumulated_data['annotated'] = True
                else:
                    response_text = "Had trouble saving that note. Let me try again."
                    next_step = "complete"
                    accumulated_data['annotated'] = False

        # Add Dad's response to history
        dad_message = {
            'role': 'assistant',
            'message': response_text,
            'timestamp': datetime.now().isoformat(),
            'step': current_step,
            'accumulated_data': accumulated_data
        }
        history.append(dad_message)

        # Update conversation in database
        self.supabase.table('gemini_conversations') \
            .update({
                'conversation_history': history,
                'updated_at': datetime.now().isoformat()
            }) \
            .eq('session_id', session_id) \
            .execute()

        return {
            'response_text': response_text,
            'next_step': next_step,
            'workout': accumulated_data.get('workout'),
            'annotated': accumulated_data.get('annotated', False),
            'session_id': session_id
        }

    def _parse_annotation_with_ai(self, text: str) -> Dict[str, Any]:
        """
        Parse workout annotation using Gemini to extract pain/injury info

        Args:
            text: User's annotation (e.g., "my knee felt tight during squats, like a 3 out of 10")

        Returns:
            {
                'pain_info': {
                    'location': str,
                    'severity': int (0-10),
                    'description': str
                }
            }
        """
        prompt = f"""
Analyze this workout note and extract any pain or injury information.

User said: "{text}"

Return ONLY valid JSON (no markdown) in this format:
{{
  "pain_info": {{
    "location": "knee",
    "severity": 3,
    "description": "felt tight during squats"
  }}
}}

If no pain mentioned, return:
{{
  "pain_info": null
}}

Rules:
- location: body part (knee, hamstring, back, shoulder, etc.)
- severity: 0-10 scale (extract from text if mentioned)
- description: brief description of the issue
"""

        try:
            response = self.model.generate_content(prompt)
            parsed_json = json.loads(response.text.strip())
            return parsed_json
        except Exception as e:
            print(f"❌ Error parsing annotation: {e}")
            return {'pain_info': None}

    def _attach_annotation_to_workout(
        self,
        workout_id: str,
        annotation_text: str,
        pain_info: Optional[Dict[str, Any]] = None
    ) -> bool:
        """
        Attach annotation to an existing workout in apple_watch_workouts

        Args:
            workout_id: Workout UUID
            annotation_text: User's full annotation text
            pain_info: Parsed pain information (optional)

        Returns:
            True if successful
        """
        try:
            # Prepare update data
            update_data = {
                'voice_notes': annotation_text,
                'notes_added_at': datetime.now().isoformat()
            }

            # Add pain info to raw_metrics JSONB if present
            if pain_info:
                # Get existing raw_metrics
                existing = self.supabase.table('apple_watch_workouts') \
                    .select('raw_metrics') \
                    .eq('id', workout_id) \
                    .execute()

                raw_metrics = existing.data[0].get('raw_metrics', {}) if existing.data else {}
                raw_metrics['pain_notes'] = pain_info

                update_data['raw_metrics'] = raw_metrics

            # Update workout record
            self.supabase.table('apple_watch_workouts') \
                .update(update_data) \
                .eq('id', workout_id) \
                .execute()

            print(f"✅ Annotation attached to workout {workout_id}")
            return True

        except Exception as e:
            print(f"❌ Error attaching annotation: {e}")
            import traceback
            traceback.print_exc()
            return False


# Example usage
if __name__ == "__main__":
    """
    Test the Gemini Flash Live system
    """
    print("=" * 70)
    print("GEMINI FLASH LIVE - TEST MODE")
    print("=" * 70)

    try:
        flash = GeminiFlashLive()

        # Test 1: Start conversation
        test_user_id = "00000000-0000-0000-0000-000000000000"

        session = flash.start_conversation(test_user_id, "morning_checkin")
        print(f"\n✅ Session started: {session['session_id']}")
        print(f"📢 Dad says: {session['greeting']}")

        # Test 2: Simulate user responses
        print("\n--- Simulating conversation flow ---")

        # Response 1: Energy level
        response1 = flash.process_voice_input(
            session_id=session['session_id'],
            user_id=test_user_id,
            text_input="I'm at a 2 today, pretty tired",
            current_step="energy_level"
        )
        print(f"\n📢 Dad says: {response1['response_text']}")

        # Response 2: Pain check
        response2 = flash.process_voice_input(
            session_id=session['session_id'],
            user_id=test_user_id,
            text_input="My knee is a little sore, nothing major",
            current_step="pain_check"
        )
        print(f"\n📢 Dad says: {response2['response_text']}")

        # Response 3: Subjective feeling
        response3 = flash.process_voice_input(
            session_id=session['session_id'],
            user_id=test_user_id,
            text_input="Just dragging a bit",
            current_step="subjective_feeling"
        )
        print(f"\n📢 Dad says: {response3['response_text']}")

        if response3.get('exercises'):
            print(f"\n📋 Selected Exercises:")
            for ex in response3['exercises']:
                print(f"   - {ex['name']} (score: {ex.get('selection_score', 'N/A')})")

    except Exception as e:
        print(f"❌ Error: {e}")
        import traceback
        traceback.print_exc()
