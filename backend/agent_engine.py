import os
import vertexai
from vertexai.generative_models import GenerativeModel, Part
from supabase import create_client, Client
from tools.google_tools import GoogleTools  # <--- NEW: Import the Eyes
from langfuse.decorators import observe  # <--- NEW: Import Observer
class NutritionAgent:
    """
    The Brain of our Application (Level 2).
    Now aware of:
    1. Memory (Supabase)
    2. Intelligence (Gemini)
    3. The World (Google Maps & Search)
    """
    def __init__(self):
        # --- 1. SETUP MEMORY (Supabase) ---
        url: str = os.environ.get("SUPABASE_URL")
        key: str = os.environ.get("SUPABASE_SERVICE_KEY")
        
        if not url or not key:
            raise ValueError("Missing Supabase Secrets!")
        self.supabase: Client = create_client(url, key)
        # --- 2. SETUP BRAIN (Gemini) ---
        vertexai.init()
        self.model = GenerativeModel("gemini-1.5-pro")
        
        # --- 3. SETUP EYES (Tools) ---
        self.tools = GoogleTools()
    @observe(as_type="generation")
    def check_user_status(self, user_id: str, lat: float = None, lng: float = None):
        """
        The Core Loop (Level 2).
        Now accepts Location (lat, lng) to see where the user is.
        """
        # --- Step A: Get Context (Memory) ---
        response = self.supabase.table("logs") \
            .select("*") \
            .eq("user_id", user_id) \
            .order("created_at", desc=True) \
            .limit(5) \
            .execute()
        recent_logs = response.data
        # --- Step B: Get World Context (The Eyes) ---
        location_context = "User location unknown."
        if lat and lng:
            # Ask Google Maps: "What is around here?"
            places = self.tools.get_places_nearby(lat, lng)
            location_context = f"User is near these places: {places}"
        # --- Step C: Construct the Prompt (The Desi Brain) ---
        system_instruction = """
        You are an elite Nutrition Coach for an Indian user. 
        Your goal is "Health with Taste" (Swasthya aur Swad).
        
        CORE PHILOSOPHY:
        1. FESTIVALS: If it is Diwali/Holi, do NOT forbid sweets. Limit portion size (e.g., "1 Kaju Katli is fine, 3 is not").
        2. STREET FOOD: If user is at a Chaat place, suggest "Steamed/Roasted" over "Fried" (e.g., Dhokla > Samosa, Idli > Vada).
        3. PROTEIN: For vegetarians, aggressively suggest Paneer, Dal, Soya, and Curd.
        4. TIMING: 
           - 5 PM is "Chai Time". Suggest Kurmura/Makhana instead of Biscuits.
           - Late Night: Suggest Haldi Doodh (Turmeric Milk) or nothing.
        """
        
        prompt = f"""
        {system_instruction}
        CONTEXT:
        1. WHO: User {user_id}
        2. MEMORY (Recent Logs): {recent_logs}
        3. LOCATION: {location_context}
        4. TIME: {self.get_current_time_str()}
        TASK:
        Analyze the Context.
        - If at a restaurant, pick the healthiest "Desi" option.
        - If hungry, suggest a time-appropriate Indian snack.
        - Tone: Encouraging, like a smart Indian friend.
        Output only JSON: 
        { 
            "action": "NOTIFICATION", 
            "message": "...", 
            "calories": 0  // If user ate something, estimate calories. Else 0.
        } 
        or 
        { "action": "NONE", "calories": 0 }
        """
        # --- Step D: Ask the Brain (Inference) ---
        # We attach the Search Tool so Gemini can "Google it" if needed.
        search_tool = self.tools.get_search_tool()
        
        chat_response = self.model.generate_content(
            prompt,
            tools=[search_tool]
        )
        return chat_response.text
    def get_current_time_str(self):
        from datetime import datetime
        return datetime.now().strftime("%A, %I:%M %p")
    def log_water(self, user_id: str):
        """
        Logs a standard glass of water (250ml) to Supabase.
        """
        try:
            self.supabase.table("logs").insert({
                "user_id": user_id,
                "type": "water",
                "content": "Drank 1L water", # Simplified for now
                "metadata": {"amount_ml": 1000}
            }).execute()
            return True
        except Exception as e:
            print(f"Error logging water: {e}")
            return False
    def undo_water(self, user_id: str):
        """
        Removes the most recent water log for the user today.
        """
        try:
            # 1. Find the latest water log
            response = self.supabase.table("logs") \
                .select("id") \
                .eq("user_id", user_id) \
                .eq("type", "water") \
                .order("created_at", desc=True) \
                .limit(1) \
                .execute()
            
            if response.data:
                log_id = response.data[0]['id']
                # 2. Delete it
                self.supabase.table("logs").delete().eq("id", log_id).execute()
                return True
            return False # No log to delete
        
        except Exception as e:  # <--- THIS WAS MISSING
            print(f"Error undoing water: {e}")
            return False
    # --- SESSION LOGIC (Phase B) ---
    def wake_up(self, user_id: str, fcm_token: str = None):
        """
        Starts a session. Sets is_active = True.
        """
        try:
            # Upsert session
            data = {
                "user_id": user_id,
                "is_active": True,
                "last_heartbeat": "now()"
            }
            if fcm_token:
                data["fcm_token"] = fcm_token
                
            self.supabase.table("agent_sessions").upsert(data).execute()
            return True
        except Exception as e:
            print(f"Error waking up: {e}")
            return False
    def heartbeat(self, user_id: str):
        """
        Updates last_heartbeat to keep the session alive.
        """
        try:
            self.supabase.table("agent_sessions") \
                .update({"last_heartbeat": "now()", "is_active": True}) \
                .eq("user_id", user_id) \
                .execute()
            return True
        except Exception as e:
            print(f"Error sending heartbeat: {e}")
            return False
    def midnight_check(self):
        """
        Runs logic to 'Sleep' all users who have been inactive or it's past midnight.
        For MVP: Just sets everyone inactive if their Heartbeat was > 2 hours ago.
        """
        try:
            # 1. Fetch stale sessions (last_heartbeat < now - 2 hours)
            # Note: Complex time logic is better done in DB Functions, but for MVP Python is fine.
            # Simplified: Just fetch all active, check time, update.
            response = self.supabase.table("agent_sessions").select("*").eq("is_active", True).execute()
            
            from datetime import datetime, timedelta, timezone
            
            active_sessions = response.data
            count_slept = 0
            
            for session in active_sessions:
                # Parse timestamp (Supabase returns ISO string)
                heartbeat_str = session['last_heartbeat']
                # Basic check: If no heartbeat?
                
                # To simplify MVP: We will assume this Function is called ONCE at Midnight by Scheduler.
                # So we just force sleep everyone.
                self.supabase.table("agent_sessions").update({"is_active": False}).eq("user_id", session['user_id']).execute()
                count_slept += 1
                
            return f"Slept {count_slept} users."
            print(f"Error in midnight check: {e}")
            return f"Error: {e}"

    # --- MULTIMODAL INTELLIGENCE (Phase C) ---

    @observe(as_type="generation")
    def process_multimodal_input(self, user_id: str, text: str = None, media_data: str = None, mime_type: str = "image/jpeg"):
        """
        Analyzes Text + Media (Image/Audio) input.
        """
        try:
            # 1. Construct the User Message Parts
            user_parts = []
            
            # Add Text if present
            if text:
                user_parts.append(text)
            
            # Add Media if present
            if media_data:
                import base64
                # Decode Base64 to bytes
                media_bytes = base64.b64decode(media_data)
                # Create Part
                media_part = Part.from_data(data=media_bytes, mime_type=mime_type)
                user_parts.append(media_part)

            if not user_parts:
                return "Empty Input"

            # 2. Add System Context
            system_instruction = """
            You are an elite Nutrition AI.
            Analyze the input (Text/Image/Audio).
            1. Identify Food: Name, Description, Healthiness.
            2. Estimate Calories: Be scientific but realistic.
            3. Advice: Give Desi/Indian context if applicable.
            4. AUDIO: If audio, transcribe it essentially and process the food/intent.
            
            Output JSON:
            {
                "message": "Start with a friendly reaction...",
                "food_name": "...",
                "calories": 0,
                "protein": 0,
                "carbs": 0,
                "fats": 0,
                "action": "LOG_FOOD"
            }
            """
            
            # 3. Call Gemini
            full_prompt = [system_instruction] + user_parts
            
            response = self.model.generate_content(full_prompt)
            
            # 4. Parse Response (Expect JSON)
            response_text = response.text
            
            # Sanitize (Gemini sometimes adds markdown backticks)
            clean_json = response_text.replace("```json", "").replace("```", "").strip()
            
            # 5. Return
            return clean_json
            
        except Exception as e:
            print(f"Error processing multimodal: {e}")
            return f'{{"message": "Error analyzing input: {str(e)}", "calories": 0}}'

    # --- DATA FEED (Phase D) ---

    def get_logs(self, user_id: str):
        """
        Fetches the last 20 logs for the user.
        """
        try:
            response = self.supabase.table("logs") \
                .select("*") \
                .eq("user_id", user_id) \
                .order("created_at", desc=True) \
                .limit(20) \
                .execute()
            
            # Helper to make datetime serializable (Supabase returns ISO strings so it's fine)
            return response.data
        except Exception as e:
            print(f"Error fetching logs: {e}")
            return []

    # --- SOS INTELLIGENCE (Phase E) ---

    @observe(as_type="generation")
    def get_sos_strategies(self, user_id: str):
        """
        Generates 3 quick, actionable strategies to fight cravings.
        """
        try:
            # Context: Can get time of day, location, or recent logs? 
            # For MVP, just simple generation.
            
            prompt = """
            User is having a craving panic (SOS).
            Generate 3 quick, short, punchy strategies to reset their mind.
            Format STRICT JSON:
            [
                {"title": "...", "description": "...", "icon": "wind", "color": "blue"},
                {"title": "...", "description": "...", "icon": "drop.fill", "color": "cyan"},
                {"title": "...", "description": "...", "icon": "figure.walk", "color": "green"}
            ]
            Keep descriptions under 10 words.
            Icons should be valid SF Symbols names if possible (e5. wind, drop.fill, figure.walk, phone.fill, leaf.fill, flame.fill).
            Colors: blue, red, orange, green, purple.
            """
            
            response = self.model.generate_content(prompt)
            clean_json = response.text.replace("```json", "").replace("```", "").strip()
            return clean_json
            
        except Exception as e:
            print(f"Error SOS: {e}")
            # Fallback
            return '[{"title": "Breathe", "description": "Inhale 4s, Hold 4s, Exhale 4s.", "icon": "lungs.fill", "color": "blue"}]'
