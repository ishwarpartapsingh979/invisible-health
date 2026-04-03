#!/usr/bin/env python3
"""
Gemini 2.0 Flash Live - Audio-to-Audio Streaming
=================================================
WebSocket server for real-time bidirectional audio conversations with Dad.

Features:
- Real-time audio streaming (low latency ~300ms)
- Dad's personality with 14 veteran rules
- All 3 conversation types: morning check-in, manual workout logging, workout annotation
- Kore voice (deep, warm, authoritative)

Architecture:
iOS App (Mic) → WebSocket → This Server → Gemini Live API → This Server → iOS App (Speaker)
"""

import os
import json
import asyncio
import logging
from typing import Dict, Any, Optional
from datetime import datetime

# WebSocket server
from aiohttp import web
import aiohttp

# Gemini
from google import genai
from google.genai.types import LiveConnectConfig, PrebuiltVoiceConfig, SpeechConfig

# Dad OS components
from dad_os_engine import DadOSEngine
from exercise_selector import ExerciseSelector
from supabase import create_client, Client

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class DadLiveAudioSession:
    """
    Manages a single audio conversation session with Dad
    """

    def __init__(
        self,
        user_id: str,
        conversation_type: str,
        websocket: web.WebSocketResponse,
        supabase: Client
    ):
        self.user_id = user_id
        self.conversation_type = conversation_type
        self.websocket = websocket
        self.supabase = supabase
        self.session_id = None
        self.gemini_session = None

        # Initialize Dad OS components
        self.dad_engine = DadOSEngine(supabase=supabase)
        self.exercise_selector = ExerciseSelector(supabase=supabase)

        # Conversation state
        self.current_step = ""
        self.conversation_data = {}

        logger.info(f"🎤 Created session for user {user_id}, type: {conversation_type}")

    async def start_gemini_session(self):
        """
        Start Gemini Live API session with Dad's personality
        """
        try:
            # Initialize Gemini client
            client = genai.Client(
                vertexai=True,
                project=os.environ.get("GOOGLE_CLOUD_PROJECT"),
                location="us-central1"
            )

            # Build Dad's system instruction with context
            system_instruction = await self._build_dad_system_instruction()

            # Configure Gemini Live session
            config = LiveConnectConfig(
                response_modalities=["AUDIO"],
                system_instruction=system_instruction,
                speech_config=SpeechConfig(
                    voice_config=PrebuiltVoiceConfig(
                        voice_name="Kore"  # Deep, warm, authoritative
                    )
                )
            )

            # Connect to Gemini Live API
            self.gemini_session = client.aio.live.connect(
                model="gemini-2.0-flash-exp",
                config=config
            )

            # Start async session
            await self.gemini_session.__aenter__()

            logger.info(f"✅ Gemini Live session started for {self.user_id}")

            # Send initial greeting
            await self._send_initial_greeting()

        except Exception as e:
            logger.error(f"❌ Failed to start Gemini session: {e}")
            raise

    async def _build_dad_system_instruction(self) -> str:
        """
        Build Dad's system instruction with rules and user context
        """
        # Get user context from Dad OS engine
        matched_rules, context = self.dad_engine.match_rules(
            user_id=self.user_id,
            self_report=None,  # Will be built during conversation
            current_hrv=None,
            current_rhr=None
        )

        # Base personality
        base_instruction = """
You are DAD - a veteran fitness coach with 30+ years of experience preventing injuries.
Your voice is warm, direct, and authoritative. You care deeply about keeping athletes healthy.

YOUR PERSONALITY:
- Speak like a wise father figure (warm but firm)
- Use analogies and real-world examples
- Never sugarcoat - tell the truth even if it's hard to hear
- Celebrate discipline, call out poor choices directly
- Keep responses SHORT (15-20 seconds max for audio)
- Use conversational language: "Listen kid...", "Here's the deal...", "Look..."

YOUR CORE RULES (14 VETERAN PRINCIPLES):
1. HEAVY WEIGHTS + UPPER ABS = INJURY - Veto weights >5kg for upper abs
2. STRIDES DAY → MINIMAL LEGS NEXT DAY
3. TIRED AFTER STRIDES → REPEAT SAME WORKOUT
4. KNEE/HAMSTRING PAIN → REDUCE IMPACT
5. POST-WORKOUT → COMPLETE THE SESSION (abs, stretching)
6. OBESE → LOW-IMPACT CARDIO
7. BAD WEATHER → INDOOR TRAINING
8. VERY TIRED + <5 MIN → LIGHT MOVEMENT
9. MUSCLE SORENESS → ACTIVE RECOVERY
10. VERY TIRED → NO GYM
11. 10-15 DAYS SOLO → ADD SPORTS
12. LOW ENGAGEMENT → VARIETY
13. DISLIKES LOW BODY POSITION → UPPER BODY FOCUS
14. LONG DAY + >10 MIN → SIMPLE BODYWEIGHT
15. HIGH INTENSITY LEGS/SHOULDERS → EXTENDED REST

AUDIO CONVERSATION STYLE:
- Speak naturally, not like reading text
- Use pauses for emphasis
- Keep responses under 20 seconds
- Ask ONE question at a time
- Wait for user's response before continuing
"""

        # Add conversation type specific instructions
        if self.conversation_type == "morning_checkin":
            base_instruction += """

CONVERSATION FLOW - MORNING CHECK-IN:
1. Start: "Good morning! Let's figure out what your body needs today. How's your energy? 1 to 5."
2. After energy: "Got it. Any pain or soreness I should know about?"
3. After pain: "Okay. How are you feeling overall? In the rhythm or dragging?"
4. After feeling: Analyze their state, match against your rules, and prescribe exercises.
5. Give specific exercise recommendations with brief rationale.
"""
        elif self.conversation_type == "manual_workout_logging":
            base_instruction += """

CONVERSATION FLOW - MANUAL WORKOUT LOGGING:
1. Start: "Hey! Tell me what you did today. What exercises, sets, and reps?"
2. After description: Confirm what you heard. "Got it - [summary]. How did it feel? 1 to 5."
3. After quality: "Copy that. Any soreness today? 0 to 10."
4. After soreness: "Perfect. Workout logged. Keep crushing it!"
"""
        elif self.conversation_type == "workout_annotation":
            base_instruction += """

CONVERSATION FLOW - WORKOUT ANNOTATION:
1. Start: "Hey! Which workout do you want to tell me about?"
2. After reference: Confirm which workout. "I see you did [workout] at [time]. What about it?"
3. After annotation: Acknowledge and log. If pain mentioned, give advice.
"""

        # Add user context
        if matched_rules:
            base_instruction += f"\n\nCURRENT USER CONTEXT:\n"
            base_instruction += f"- {len(matched_rules)} of your rules are triggered today\n"

            # Extract vetoes and forces
            vetoes = []
            forces = []
            for rule in matched_rules:
                vetoes.extend(rule.get('action_vetoes', []))
                forces.extend(rule.get('action_forces', []))

            if vetoes:
                base_instruction += f"- AVOID: {', '.join(vetoes)}\n"
            if forces:
                base_instruction += f"- RECOMMEND: {', '.join(forces)}\n"

        return base_instruction

    async def _send_initial_greeting(self):
        """
        Send Dad's initial greeting based on conversation type
        """
        greetings = {
            "morning_checkin": "Good morning! Let's figure out what your body needs today. How's your energy? 1 to 5.",
            "manual_workout_logging": "Hey! Tell me what you did today. What exercises, sets, and reps?",
            "workout_annotation": "Hey! Which workout do you want to tell me about?"
        }

        greeting = greetings.get(self.conversation_type, "Hey there! How can I help?")

        # Send greeting as text (Gemini will convert to audio)
        await self.gemini_session.send(greeting, end_of_turn=True)

        # Set initial step
        if self.conversation_type == "morning_checkin":
            self.current_step = "energy_level"
        elif self.conversation_type == "manual_workout_logging":
            self.current_step = "parse_workout"
        elif self.conversation_type == "workout_annotation":
            self.current_step = "identify_workout"

    async def process_audio_from_ios(self, audio_data: bytes):
        """
        Process incoming audio from iOS app
        Send to Gemini Live API
        """
        try:
            # Send audio to Gemini
            await self.gemini_session.send(audio_data, end_of_turn=True)

        except Exception as e:
            logger.error(f"❌ Error processing iOS audio: {e}")

    async def stream_audio_to_ios(self):
        """
        Stream Gemini's audio responses to iOS
        """
        try:
            async for response in self.gemini_session.receive():
                # Handle different response types
                if response.data:
                    # Audio data from Gemini
                    await self.websocket.send_bytes(response.data)

                if response.text:
                    # Text transcript (for accessibility)
                    await self.websocket.send_json({
                        "type": "transcript",
                        "text": response.text,
                        "is_dad": True
                    })

                # Check if turn is complete
                if response.server_content and response.server_content.turn_complete:
                    # Handle conversation flow logic
                    await self._handle_turn_complete(response.text)

        except Exception as e:
            logger.error(f"❌ Error streaming to iOS: {e}")

    async def _handle_turn_complete(self, text: Optional[str]):
        """
        Handle conversation flow when Gemini completes a turn
        """
        # This is where we'd update conversation state, log to database, etc.
        # For now, just log
        logger.info(f"✅ Turn complete. Current step: {self.current_step}")

        # TODO: Implement state management for workout logging and annotation
        # - Parse responses
        # - Update database
        # - Trigger exercise selection when ready

    async def close(self):
        """
        Clean up session
        """
        try:
            if self.gemini_session:
                await self.gemini_session.__aexit__(None, None, None)
            logger.info(f"🔚 Session closed for {self.user_id}")
        except Exception as e:
            logger.error(f"❌ Error closing session: {e}")


# Global session storage
active_sessions: Dict[str, DadLiveAudioSession] = {}


async def websocket_handler(request):
    """
    WebSocket endpoint handler
    """
    ws = web.WebSocketResponse()
    await ws.prepare(request)

    logger.info("🔌 New WebSocket connection")

    # Initialize session variables
    session = None

    try:
        # Wait for initial handshake with user_id and conversation_type
        async for msg in ws:
            if msg.type == aiohttp.WSMsgType.TEXT:
                data = json.loads(msg.data)

                if data.get("action") == "start":
                    # Start new session
                    user_id = data.get("user_id")
                    conversation_type = data.get("conversation_type", "morning_checkin")

                    # Get Supabase client
                    supabase = create_client(
                        os.environ.get("SUPABASE_URL"),
                        os.environ.get("SUPABASE_SERVICE_KEY")
                    )

                    # Create session
                    session = DadLiveAudioSession(
                        user_id=user_id,
                        conversation_type=conversation_type,
                        websocket=ws,
                        supabase=supabase
                    )

                    # Start Gemini session
                    await session.start_gemini_session()

                    # Store session
                    session_id = f"{user_id}_{datetime.now().timestamp()}"
                    active_sessions[session_id] = session

                    # Send confirmation
                    await ws.send_json({
                        "type": "session_started",
                        "session_id": session_id
                    })

                    # Start streaming responses from Gemini
                    asyncio.create_task(session.stream_audio_to_ios())

                elif data.get("action") == "stop":
                    # End session
                    break

            elif msg.type == aiohttp.WSMsgType.BINARY:
                # Audio data from iOS
                if session:
                    await session.process_audio_from_ios(msg.data)

            elif msg.type == aiohttp.WSMsgType.ERROR:
                logger.error(f'❌ WebSocket error: {ws.exception()}')
                break

    except Exception as e:
        logger.error(f"❌ WebSocket handler error: {e}")
        import traceback
        traceback.print_exc()

    finally:
        # Clean up
        if session:
            await session.close()

        logger.info("🔌 WebSocket connection closed")

    return ws


async def health_check(request):
    """
    Health check endpoint for Cloud Run
    """
    return web.Response(text="OK")


def create_app():
    """
    Create aiohttp application
    """
    app = web.Application()
    app.router.add_get('/health', health_check)
    app.router.add_get('/ws', websocket_handler)
    return app


if __name__ == '__main__':
    app = create_app()

    # Cloud Run provides PORT environment variable
    port = int(os.environ.get('PORT', 8080))

    logger.info(f"🚀 Starting Dad Live Audio Server on port {port}")

    web.run_app(app, host='0.0.0.0', port=port)
