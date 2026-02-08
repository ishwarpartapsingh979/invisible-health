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
        self.model = GenerativeModel(
            "gemini-2.5-pro",
            generation_config={"response_mime_type": "application/json"}
        )
        
        # --- 3. SETUP EYES (Tools) ---
        self.tools = GoogleTools()
    @observe(as_type="generation")
    def check_user_status(self, user_id: str, lat: float = None, lng: float = None, steps: int = None):
        """
        The Core Loop (Level 2).
        Now accepts Location (lat, lng) and Steps.
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
        
        # Phase F: Steps Context
        steps_context = f"STEPS TODAY: {steps}" if steps is not None else "STEPS: Unknown"
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
        5. ACTIVITY: Praise high steps (>8000). Encourage low steps (<3000).
        """
        
        prompt = f"""
        {system_instruction}
        CONTEXT:
        1. WHO: User {user_id}
        2. MEMORY (Recent Logs): {recent_logs}
        3. LOCATION: {location_context}
        4. ACTIVITY: {steps_context}
        5. TIME: {self.get_current_time_str()}
        TASK:
        Analyze the Context.
        - If at a restaurant, pick the healthiest "Desi" option.
        - If hungry, suggest a time-appropriate Indian snack.
        - If steps are high, congratulate them.
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
    @observe()
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
    @observe()
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
    @observe()
    def wake_up(self, user_id: str, fcm_token: str = None, steps: int = None):
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
            if steps:
                # We could log steps here too, but for now just acknowledging receipt
                pass
                
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
        except Exception as e:
            print(f"Error in midnight check: {e}")
            return f"Error: {e}"
    # --- MULTIMODAL INTELLIGENCE (Phase C) ---
    @observe(as_type="generation")
    def process_multimodal_input(self, user_id: str, text: str = None, media_data: str = None, mime_type: str = "image/jpeg", lat: float = None, lng: float = None):
        """
        Analyzes Text + Media (Image/Audio) input.
        Now supports Location context and Observability.
        """
        # Fix: langfuse_context is in decorators, not top level
        from langfuse.decorators import langfuse_context
        
        try:
            # 1. Construct the User Message Parts
            user_parts = []
            log_input_text = ""
            
            # Add Text if present
            if text:
                user_parts.append(text)
                log_input_text += f"[TEXT]: {text} "
            
            # Add Media if present
            if media_data:
                import base64
                # Decode Base64 to bytes
                media_bytes = base64.b64decode(media_data)
                # Create Part
                media_part = Part.from_data(data=media_bytes, mime_type=mime_type)
                user_parts.append(media_part)
                log_input_text += "[IMAGE/MEDIA UPLOADED]"
                
            if not user_parts:
                return "Empty Input"
            
            # --- CONTEXT: Fetch Recent Logs (Phase H) ---
            recent_logs = []
            try:
                # Reuse existing get_logs but limited to 5
                log_response = self.supabase.table("logs").select("food_name, calories, created_at").eq("user_id", user_id).order("created_at", desc=True).limit(5).execute()
                recent_logs = log_response.data
            except Exception as e:
                print(f"Failed to fetch context: {e}")
            
            context_str = "No recent logs."
            if recent_logs:
                context_str = "RECENTLY EATEN:\n" + "\n".join([f"- {l.get('food_name')} ({l.get('calories')} kcal)" for l in recent_logs])
            
            # --- LOCATION CONTEXT (Phase 2.1) ---
            location_context = "Location: Unknown"
            if lat and lng:
                try:
                    places = self.tools.get_places_nearby(lat, lng)
                    location_context = f"User Location Context: {places}"
                except Exception as e:
                    print(f"Failed to fetch location: {e}")
            
            # 2. Add System Context
            system_instruction = f"""
            You are an elite Nutrition AI.
            
            CURRENT CONTEXT:
            {context_str}
            {location_context}
            
            Analyze the input (Text/Image/Audio).
            """ + """
            1. IDENTIFY FOOD: Name, Description, Healthiness.
               - If it's a BRAND (e.g., McDonald's, Starbucks), use their official calorie counts.
               - Detect if the user says "Yesterday" or "Last Night". Parsing: date_offset should be -1.
               - IF IMAGE + TEXT: Use the text to interpret the image (e.g. "This is a small portion").
            
            2. ESTIMATE CALORIES: Be scientific.
            
            3. ADVICE: Give Desi/Indian context if applicable.
            
            4. CRAVINGS: If user says "I am craving X", suggest a HEALTHY ALTERNATIVE.
               - Action should be "CRAVING_HELP".
               - Food Name: The healthy alternative.
            
            Output JSON:
            {
                "message": "Start with a friendly reaction...",
                "food_name": "...",
                "calories": 0,
                "protein": 0,
                "carbs": 0,
                "fats": 0,
                "action": "LOG_FOOD" (or "CRAVING_HELP"),
                "date_offset": 0 (defaults to 0, -1 for yesterday)
            }
            """
            
            # 3. Call Gemini
            full_prompt = [system_instruction] + user_parts
            
            response = self.model.generate_content(full_prompt)
            
            # 4. Parse Response (Expect JSON)
            response_text = response.text
            
            # --- OBSERVABILITY: Log Metrics (Phase 2.1) ---
            try:
                usage = response.usage_metadata
                langfuse_context.update_current_observation(
                    input=log_input_text,
                    output=response_text,
                    usage={
                        "input": usage.prompt_token_count,
                        "output": usage.candidates_token_count,
                        "total": usage.total_token_count
                    }
                )
            except Exception as e:
                print(f"Observability Log Failed: {e}")
            
            # Sanitize (Gemini sometimes adds markdown backticks)
            clean_json = response_text.replace("```json", "").replace("```", "").strip()
            
            # --- SAVE TO MEMORY (Supabase) ---
            import json
            try:
                log_data = json.loads(clean_json)
                
                # Check Action
                action = log_data.get("action", "").upper()
                print(f"🕵️‍♂️ Gemini Action: {action}")
                
                # Extract Message for Saving
                ai_message = log_data.get("message", "No analysis provided.")
                
                # Check Date Offset (Handle "Yesterday")
                date_offset = log_data.get("date_offset", 0)
                
                # Only save if it's a food log
                if action == "LOG_FOOD":
                     # Handle Potential Strings in Numbers (Gemini quirks)
                     calories = log_data.get("calories", 0)
                     if isinstance(calories, str): calories = int(calories) if calories.isdigit() else 0
                     
                     # Calculate Created At based on Offset
                     # Note: Supabase expects ISO string. We can rely on default now() for today, but for yesterday we need to compute.
                     # However, Python timezones are tricky. Simplest: Let Backend save "created_at" explicitly only if offset != 0.
                     
                     record = {
                         "user_id": user_id,
                         "food_name": log_data.get("food_name", "Unknown Food"),
                         "calories": calories,
                         "protein": log_data.get("protein", 0),
                         "carbs": log_data.get("carbs", 0),
                         "fats": log_data.get("fats", 0),
                         "image_url": "placeholder",
                         "ai_analysis_json": log_data, # Store full JSON for future proofing
                         "message": ai_message # Store commentary for Display
                     }
                     
                     # Handle Yesterday logic
                     if date_offset != 0:
                         from datetime import datetime, timedelta
                         # Using UTC for simplicity, in prod user timezone matters
                         past_date = datetime.utcnow() + timedelta(days=date_offset)
                         record["created_at"] = past_date.isoformat()
                     
                     print(f"⏳ Inserting into Supabase: {record}")
                     
                     # Fire and Forget Insert
                     response = self.supabase.table("logs").insert(record).execute()
                     print(f"✅ Supabase Insert Success: {response}")
                     log_data["_debug"] = f"Supabase SAVED: {response.data}"
                     
                else:
                    print(f"⚠️ Skipping Insert. Action was: {action}")
                    log_data["_debug"] = f"Supabase SKIPPED: Action was {action}"
                    
            except Exception as e:
                print(f"⚠️ Error saving to Supabase: {e}")
                import traceback
                traceback.print_exc()
                log_data["_debug"] = f"Supabase ERROR: {str(e)}"
            
            # 5. Return (Serialize back to JSON String with the debug info)
            return json.dumps(log_data)
            
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
            
    def update_log(self, log_data: dict):
        """
        Updates an existing log entry.
        Triggers RE-CALCULATION if name changes massively.
        """
        try:
            log_id = log_data.get("id")
            if not log_id: raise ValueError("Missing log_id")
            
            new_name = log_data.get("food_name")
            new_cals = log_data.get("calories")
            
            # RECALCULATION LOGIC (Phase 2.1)
            # If name is present, but cals are 0 or None, we MUST recalc.
            # Ideally we check if name changed from DB, but for now we trust the client logic (Client sends 0 cals if name changed).
            should_recalc = (new_name and (new_cals is None or new_cals == 0 or new_cals == "0"))
            
            if should_recalc:
                print(f"🔄 Recalculating macros for: {new_name}")
                # Call Gemini for just this text
                recalc_prompt = f"""
                You are a Nutrition AI.
                Analyze this food: "{new_name}"
                Return JSON:
                {{
                    "calories": 0,
                    "protein": 0,
                    "carbs": 0,
                    "fats": 0,
                    "message": "Updated macros for {new_name}"
                }}
                """
                response = self.model.generate_content(recalc_prompt)
                clean_json = response.text.replace("```json", "").replace("```", "").strip()
                import json
                ai_data = json.loads(clean_json)
                
                # Merge into our update payload
                log_data["calories"] = ai_data.get("calories")
                log_data["protein"] = ai_data.get("protein")
                log_data["carbs"] = ai_data.get("carbs")
                log_data["fats"] = ai_data.get("fats")
                log_data["message"] = ai_data.get("message")
            
            # Construct Update Payload
            updates = {
                "food_name": log_data.get("food_name"),
                "calories": log_data.get("calories"),
                "protein": log_data.get("protein"),
                "carbs": log_data.get("carbs"),
                "fats": log_data.get("fats"),
                "message": log_data.get("message")
            }
            # Remove None values
            updates = {k: v for k, v in updates.items() if v is not None}
            
            response = self.supabase.table("logs").update(updates).eq("id", log_id).execute()
            print(f"✅ Log Updated: {response}")
            return True, "Log Updated"
        except Exception as e:
            print(f"Error updating log: {e}")
            return False, str(e)

    # --- SOS INTELLIGENCE (Phase E) ---
    @observe(as_type="generation")
    def get_sos_strategies(self, user_id: str, user_input: str = None):
        """
        Generates 3 quick, actionable strategies to fight cravings.
        Customizes based on user_input if provided (e.g., "Craving Chips").
        """
        try:
            # Context: Can get time of day, location, or recent logs?
            
            prompt = """
            You are a tough but caring nutrition coach. The user is in panic mode (SOS).
            """
            
            if user_input:
                prompt += f"\nUser says: '{user_input}'. Suggest 3 specific alternatives or strategies for this craving."
            else:
                prompt += "\nGenerate 3 generic, high-impact strategies to stop binge eating immediately."
                
            prompt += """
            Output JSON List:
            [
                {"title": "...", "description": "...", "icon": "leaf.fill" (SF Symbol), "color": "blue" (or red/green/orange/purple)}
            ]
            """
            
            response = self.model.generate_content(prompt)
            clean_json = response.text.replace("```json", "").replace("```", "").strip()
            
            return clean_json
        except Exception as e:
            print(f"Error generating SOS: {e}")
            # Fallback
            return '[{"title": "Drink Water", "description": "Hydrate first.", "icon": "drop.fill", "color": "blue"}]'
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
    # --- PHASE 3.1: WORKOUT ANALYSIS ---
    @observe(as_type="generation")
    def analyze_workout(self, data: dict):
        """
        Analyzes workout metrics. 
        Uses "Olympic Coach Personas" if comprehensive data is present.
        Falls back to Legacy logic if not.
        """
        try:
            # Common Data
            user_id = data.get('user_id')
            w_type_raw = str(data.get('workout_type', 'Workout')) # "52", "37" etc
            duration = int(float(data.get('duration_seconds', 0))) // 60
            cals = int(float(data.get('calories', 0)))
            logs_context = data.get('logs', "No notes found.")
            
            # Check for New "Olympic" Metrics
            metrics_dict = data.get("metrics")
            
            if metrics_dict:
                # --- OLYMPIC LEVEL ANALYSIS ---
                return self._analyze_workout_olympic(w_type_raw, duration, cals, logs_context, metrics_dict)
            
            # --- LEGACY FALLBACK (Existing Logic) ---
            osc = data.get('avg_oscillation_cm', 0)
            gct = data.get('avg_gct_ms', 0)
            pwr = data.get('avg_power_watts', 0)
            avg_hr = data.get('avg_hr', 0)
            max_hr = data.get('max_hr', 0)
            
            is_running_legacy = "52" in w_type_raw or "running" in w_type_raw.lower()
            
            if is_running_legacy:
                prompt = f"""
                You are an Elite Sports Scientist & Biomechanics Coach.
                
                Analyze this RUNNING Session:
                - Duration: {duration} mins
                - Calories: {cals}
                - Vertical Oscillation: {osc} cm (Target < 8 cm)
                - Ground Contact Time: {gct} ms (Target < 200 ms)
                - Power: {pwr} W
                - Heart Rate: Avg {avg_hr} bpm, Max {max_hr} bpm
                - Context Notes: "{logs_context}"
                
                TASK:
                1. DEMYSTIFY: Explain metrics simply.
                2. CRITIQUE: Form feedback based on Oscillation/GCT.
                3. CONTEXT: If user notes say "Tired" or "Intervals", relate it to the data.
                
                OUTPUT JSON:
                {{ "message": "..." }}
                """
            else:
                prompt = f"""
                You are an Elite Strength & Conditioning Coach.
                
                Analyze this STRENGTH/GYM Session:
                - Duration: {duration} mins
                - Calories: {cals}
                - Heart Rate: Avg {avg_hr} bpm, Max {max_hr} bpm
                - Context Notes (User Logs): "{logs_context}"
                
                TASK:
                1. ANALYZE INTENSITY: Based on HR & Duration. (e.g. "Hypertrophy zone" vs "Endurance").
                2. LOG CORRELATION: Look at the 'Context Notes'. 
                   - If user logged "Chest Day", "Legs", or specific lifts, USE THAT.
                   - Example: "Good intensity for a Leg Day. Your HR spike of {max_hr} suggests heavy squat sets."
                   - If notes are empty, ask user to log specific lifts next time for better feedback.
                3. RECOVERY TIP: Based on the session load.
                
                OUTPUT JSON:
                {{ "message": "..." }}
                """
            
            response = self.model.generate_content(prompt)
            clean_json = response.text.replace("```json", "").replace("```", "").strip()
            return clean_json
            
        except Exception as e:
            return f'{{"message": "Error analyzing workout: {str(e)}"}}'

    def _analyze_workout_olympic(self, w_type: str, duration: int, cals: int, logs: str, metrics: dict):
        """
        Specialized Olympic Coach Logic based on Workout Type.
        """
        # Parse Type
        # Common HKWorkoutActivityType Raw Values:
        # 52: Running, 37: Traditional Strength, 20: Functional Strength, 
        # 46: Swimming, 13: Cycling, 63: HIIT, 57: Yoga, 24: Hiking, 52: Walking? No Walking is 52?? No Running is 52. Walking is 52? Wait.
        # Running: 52
        # Walking: 52?? No. 
        # Let's rely on string matching if raw values are ambiguous or just use general buckets.
        
        # Determine Persona
        persona = "General Coach"
        guidelines = "Analyze Heart Rate and Effort."
        
        # 1. RUNNING (Outdoor vs Indoor)
        if "52" in w_type or "running" in w_type.lower():
            # Check for GPS/Biomechanics signals
            has_gps = metrics.get('avg_stride_len', 0) > 0 or metrics.get('distance_meters', 0) > 0
            has_biomech = metrics.get('avg_oscillation_cm', 0) > 0
            
            if has_biomech:
                persona = "The Biomechanist (Olympic Running Coach)"
                guidelines = """
                Focus deeply on FORM efficiency.
                - Vertical Oscillation: < 8cm is elite. > 10cm is bouncing.
                - GCT: < 200ms is elite. > 250ms is plodding.
                - Power: Relate watts to pace.
                """
            else:
                persona = "The Pacer (Indoor Run Specialist)"
                guidelines = """
                Focus on EFFICIENCY and CARDIAC DRIFT.
                - Cadence: Target 170-180 spm. If lower, suggest shorter strides.
                - HR vs Pace: If HR rose but pace stayed same, note 'Cardiac Drift'.
                - Since no GPS/Biomechanics, assume Treadmill.
                """
                
        # 2. STRENGTH (Traditional/Functional)
        elif "37" in w_type or "20" in w_type or "strength" in w_type.lower():
            persona = "The Hypertrophy Expert"
            guidelines = """
            Focus on INTENSITY and TIME UNDER TENSION.
            - Analyze HR Peaks: Do they match sets (spikes) vs rest (drops)?
            - Rest Intervals: If HR stays high, it's Circuit/Endurance. If it drops, it's Strength/Power.
            - Context: Use the user's logs (e.g. "Leg Day") to validate the HR spikes.
            """
            
        # 3. HIIT
        elif "63" in w_type or "hiit" in w_type.lower():
            persona = "The Metabolic Conditioning Coach"
            guidelines = """
            Focus on RECOVERY RATE.
            - Look at the difference between Max HR and Avg HR.
            - Are they recovering fast enough between intervals?
            - Sustain: Did they crash at the end?
            """
            
        # 4. YOGA / MIND
        elif "57" in w_type or "yoga" in w_type.lower():
            persona = "The Mindfulness Guide"
            guidelines = "Focus on Heart Rate variability and calmness. Lower HR is better."

        # 5. SOCCER / TEAM SPORTS
        elif "soccer" in w_type.lower() or "football" in w_type.lower() or "rugby" in w_type.lower():
            persona = "The Team Trophy Scout"
            guidelines = """
            Focus on WORK RATE (Volume) vs INTENSITY (Bursts).
            - Distance: Relate total meters to position (e.g. Midfielders run more).
            - Heart Rate: High Avg HR means high engagement.
            - Fade: Did they maintain intensity?
            """
            
        # 6. RACKET SPORTS (Table Tennis, Tennis)
        elif "tennis" in w_type.lower() or "squash" in w_type.lower() or "badminton" in w_type.lower():
            persona = "The Reflex Coach"
            guidelines = """
            Focus on AGILITY and READINESS.
            - Active Calories: High burn means good footwork.
            - HR Variability in session: Jagged is good (rallies). Flat is lazy.
            """
            
        # 7. CYCLING
        elif "13" in w_type or "cycling" in w_type.lower():
            persona = "The Tour Directuer"
            guidelines = """
            Focus on POWER (Watts) and EFFICIENCY.
            - If Power exists: Calculate Watts/Kg (guess weight if unknown or generic).
            - Cadence: Ideal is 80-90RPM. If lower, suggest gearing down.
            """
            
        # 8. SWIMMING
        elif "46" in w_type or "swimming" in w_type.lower():
            persona = "The Aquatics Director"
            guidelines = """
            Focus on HYDRODYNAMICS.
            - Stroke Count: Lower is better (more distance per stroke).
            - Pace: Consistency across laps (if dist available).
            """
            
        # 9. SNOW SPORTS
        elif "skiing" in w_type.lower() or "snowboarding" in w_type.lower():
            persona = "The Alpine Guide"
            guidelines = """
            Focus on VERTICAL and SPEED.
            - Descent: Total distance downhill.
            - HR: Adrenaline spikes vs steady cardio.
            """
            
        # 10. GOLF
        elif "golf" in w_type.lower():
            persona = "The Caddie"
            guidelines = """
            Focus on WALKING FITNESS and FOCUS.
            - Distance: Did they walk the course? Good cardio base.
            - HR: Should be low/steady for focus. Spikes might mean stress/bad shots.
            """
            
        
        # Goal Context Injection
        goal_instruction = ""
        if "[GOAL_CONTEXT]" in logs:
            goal_instruction = """
            SPECIAL INSTRUCTION: GOAL TRAJECTORY
            The user has a defined Goal (see User Notes). You MUST add a section called '🎯 Goal Trajectory' with two distinct paths based on this workout's data:
            1. The Finisher Path: Are they on track to finish safely? If not, what is the minimum fix?
            2. The Winner/PB Path: What SPECIFICALLY needs to improve to Win or Personal Best? (e.g. 'To win, you need to increase Avg Power by 20W').
            """

        # Construct the Olympic Prompt
        prompt = f"""
        You are {persona}.
        
        SESSION DATA:
        - Type: {w_type}
        - Duration: {duration} min
        - Calories: {cals}
        - User Notes: "{logs}"
        
        DEEP METRICS (HealthKit):
        {metrics}
        
        GUIDELINES:
        {guidelines}
        
        {goal_instruction}
        
        TASK:
        1. DEEP DIVE: Don't just summarize. Find the 'One Big Thing' they did wrong or right.
        2. USE THE DATA: Cite specific numbers from the 'DEEP METRICS' block.
           - E.g. "Your Cadence of {metrics.get('avg_cadence', 'N/A')} was too low for this pace."
        3. BE SPECIFIC: Give one actionable correction for next time.
        
        OUTPUT JSON:
        { "message": "Your detailed analysis here..." }
        """
        
        response = self.model.generate_content(prompt)
        clean_json = response.text.replace("```json", "").replace("```", "").strip()
        return clean_json
        
    # --- PHASE 3.3: NIGHTLY REPORT ---
    @observe(as_type="generation")
    def generate_nightly_report(self, data: dict):
        """
        Synthesizes Food vs Workouts vs Bio-Readiness.
        """
        try:
            steps = data.get('steps', 0)
            workouts = data.get('workouts', "None")
            vo2 = data.get('vo2', 0)
            hrv = data.get('hrv', 0)
            rhr = data.get('rhr', 0)
            
            # Fetch today's food logs
            user_id = data.get('user_id')
            today_logs = []
            try:
                # In real prod, filter by date. Here we take last 10, assuming they are today.
                logs_resp = self.supabase.table("logs").select("food_name, calories").eq("user_id", user_id).order("created_at", desc=True).limit(10).execute()
                today_logs = logs_resp.data
            except: pass
            
            total_cals_in = sum([l.get('calories', 0) for l in today_logs])
            food_summary = ", ".join([l.get('food_name') for l in today_logs])
            
            prompt = f"""
            You are a Holistic Health Coach generating the 'Nightly Report'.
            
            DATA:
            1. ENGINE (Output): {steps} steps. Workouts: {workouts}.
            2. FUEL (Input): {total_cals_in} kcal. Foods: {food_summary}.
            3. CHASSIS (Recovery): VO2Max {vo2}, HRV {hrv}ms, Resting HR {rhr}bpm.
            
            TASK:
            Compare Fuel vs Engine. 
            - If Output > Input: "Deficit Day". Warn about recovery if HRV is low.
            - If Input > Output: "Surplus Day". Fine for building, bad for fat loss.
            - Analyze HRV: If < 30ms (assumption), suggest sleep focus.
            
            OUTPUT JSON:
            {{ "message": "..." }}
            """
            
            response = self.model.generate_content(prompt)
            clean_json = response.text.replace("```json", "").replace("```", "").strip()
            return clean_json
            
        except Exception as e:
             return f'{{"message": "Error generating report: {str(e)}"}}'

    # --- PHASE 3.4: CHAT WITH CONTEXT ---
    @observe(as_type="generation")
    def chat_with_context(self, data: dict):
        """
        Chat that knows *everything*: Steps, Recent Logs, Location, HRV.
        """
        try:
            user_id = data.get('user_id')
            user_msg = data.get('message')
            
            # Context passed from client (or we could fetch it here)
            # For speed, let's trust client passed critical metrics, or we fetch logs.
            # Let's fetch logs here to be safe.
            recent_logs = self.get_logs(user_id)[:5] # Get last 5
            
            steps = data.get('steps', 0)
            hrv = data.get('hrv', 0)
            location = data.get('location_context', "Unknown")
            
            prompt = f"""
            You are the user's Intelligent Health Companion.
            
            CONTEXT:
            - User: {user_msg}
            - Recent Food: {[l['food_name'] for l in recent_logs]}
            - Activity: {steps} steps.
            - Recovery: HRV {hrv} ms.
            - Location: {location}
            
            INSTRUCTIONS:
            Answer the user's question accurately.
            Use the context! 
            - If they ask "Can I eat pizza?", check if they walked enough or have high compliance.
            - If HRV is low, be gentle.
            
            OUTPUT JSON:
            {{ "message": "..." }}
            """
            
            response = self.model.generate_content(prompt)
            clean_json = response.text.replace("```json", "").replace("```", "").strip()
            return clean_json
            
        except Exception as e:
            return f'{{"message": "I am having trouble thinking right now. ({str(e)})"}}'
