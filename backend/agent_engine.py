import os
import json
import base64
import vertexai
from vertexai.generative_models import GenerativeModel, Part
from supabase import create_client, Client
from tools.google_tools import GoogleTools  # <--- NEW: Import the Eyes
from langfuse.decorators import observe  # <--- NEW: Import Observer
from grocery_tools import GroceryTools  # <--- NEW: Import Grocery/Food MCP Tools
from rule_extractor import (  # <--- NEW: Import Dad OS Rule Extractor
    convert_to_m4a,
    upload_to_storage,
    transcribe_audio,
    extract_rule_with_gemini,
    validate_and_insert_rule
)
class NutritionAgent:
    """
    The Brain of our Application (Level 2 + MCP Integration).
    Now aware of:
    1. Memory (Supabase)
    2. Intelligence (Gemini)
    3. The World (Google Maps & Search)
    4. Food Ecosystem (Swiggy, Zepto, Zomato via MCP)
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

        # --- 4. SETUP FOOD DELIVERY (MCP Tools) ---
        try:
            self.grocery_tools = GroceryTools()
            print("✅ MCP Grocery Tools initialized (Swiggy, Zepto, Zomato)")
        except Exception as e:
            print(f"⚠️ MCP Tools initialization failed: {str(e)}")
            self.grocery_tools = None
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
    def _clean_and_validate_json(self, raw_text: str):
        import json
        try:
            # 1. Strip Code Blocks
            clean = raw_text.replace("```json", "").replace("```", "").strip()
            # 2. Try Parse
            parsed = json.loads(clean)
            return json.dumps(parsed)
        except:
            # 3. Fuzzy Find JSON
            try:
                start = raw_text.find('{')
                end = raw_text.rfind('}') + 1
                if start != -1 and end > start:
                    clean = raw_text[start:end]
                    parsed = json.loads(clean)
                    return json.dumps(parsed)
            except: pass
            
            # 4. Fail Safe: Wrap as Message
            return json.dumps({"message": raw_text})

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
            
            raw_response = ""
            
            if metrics_dict:
                # --- OLYMPIC LEVEL ANALYSIS ---
                raw_response = self._analyze_workout_olympic(w_type_raw, duration, cals, logs_context, metrics_dict)
            
            else:
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
                raw_response = response.text
                
            return self._clean_and_validate_json(raw_response)
            
        except Exception as e:
            return f'{{"message": "Error analyzing workout: {str(e)}"}}'

    def _analyze_workout_olympic(self, w_type: str, duration: int, cals: int, logs: str, metrics: dict):
        """
        Specialized Olympic Coach Logic based on Workout Type.
        """
        # --- VIDEO LIBRARY (Curated Searches) ---
        VIDEO_LIBRARY = {
            "run_cadence_drill": "https://www.youtube.com/results?search_query=running+cadence+180+spm+drill+shorts", # Robust Search
            "run_overstriding_fix": "https://www.youtube.com/results?search_query=fix+running+overstriding+drill+shorts",
            "strength_rest_periods": "https://www.youtube.com/results?search_query=strength+training+rest+periods+science+shorts",
            "strength_eccentric_loading": "https://www.youtube.com/results?search_query=time+under+tension+hypertrophy+shorts",
            "hiit_box_breathing": "https://www.youtube.com/results?search_query=box+breathing+technique+shorts",
            "warmup_dynamic": "https://www.youtube.com/results?search_query=dynamic+warmup+runner+shorts"
        }
        
        # Parse Type from Explicit Name if available, else fallback to raw
        w_name = metrics.get("workout_name", "Workout")
        is_indoor = metrics.get("is_indoor", False)
        
        # Determine Persona based on Name/Indoor status
        persona = "General Coach"
        guidelines = "Analyze Heart Rate and Effort."
        
        # 1. RUNNING
        if "Running" in w_name:
            if is_indoor:
                persona = "The Pacer (Indoor Run Specialist)"
                guidelines = """
                User ran INDOORS (likely Treadmill).
                Focus on EFFICIENCY and METABOLIC COST.
                - DATA CHECK: You have Cadence inside 'DEEP METRICS'. Use it.
                - Cadence Audit: Target 170-180 spm. If lower, suggest shorter strides.
                - Cardiac Drift: Compare Avg HR vs Max HR. If HR climbed steadily, it's 'Drift'.
                - Intensity Check: Compare 'Active Calories' vs 'Duration'. Is the burn rate > 12kcal/min?
                - TREADMILL TIP: Remind them that 0% incline is easier than road. Suggest 1% for realism.
                """
            else:
                persona = "The Biomechanist (Olympic Running Coach)"
                guidelines = """
                User ran OUTDOORS.
                Focus deeply on FORM efficiency and CARDIO.
                - Vertical Oscillation: < 8cm is elite. > 10cm is bouncing.
                - GCT: < 200ms is elite. > 250ms is plodding.
                - Power: Relate watts to pace (if available).
                """

        # 2. STRENGTH
        elif "Strength" in w_name or "Functional" in w_name or "Cross" in w_name:
            persona = "The Hypertrophy Expert"
            guidelines = """
            Focus on INTENSITY and TIME UNDER TENSION.
            IMPORTANT: We do NOT know the weight lifted. Do not guess.
            1. Analyze HR Peaks: Do they match sets (spikes) vs rest (drops)?
            2. Rest Intervals: If HR stays high, it's Circuit/Endurance. If it drops, it's Strength/Power.
            3. Context: Use the user's logs (e.g. "Leg Day") to validate the HR spikes.
            4. ADVICE: If HR graph is flat, suggest they might not be resting enough to lift heavy.
            """

        # 3. HIIT
        elif "HIIT" in w_name:
            persona = "The Metabolic Conditioning Coach"
            guidelines = """
            Focus on RECOVERY RATE.
            - Look at the difference between Max HR and Avg HR.
            - Are they recovering fast enough between intervals?
            - Sustain: Did they crash at the end?
            """
            
        # 4. YOGA
        elif "Yoga" in w_name:
            persona = "The Mindfulness Guide"
            guidelines = "Focus on Heart Rate variability and calmness. Lower HR is better."
            
        # 5. CYCLING
        elif "Cycling" in w_name:
            if is_indoor:
                persona = "The Peloton Pro"
                guidelines = """
                Focus on POWER CONSISTENCY.
                - If Power (Watts) is available, use it.
                - If not, use HR Zones.
                """
            else:
                persona = "The Tour Directuer"
                guidelines = """
                Focus on AEROBIC BASE.
                - Distance vs Time.
                - Cadence: Ideal is 80-90RPM.
                """
        
        # 6. SWIMMING
        elif "Swimming" in w_name:
            persona = "The Aquatics Director"
            guidelines = """
            Focus on HYDRODYNAMICS.
            - Stroke Count: Lower is better (more distance per stroke).
            - Pace: Consistency across laps.
            """

        # 7. SPORTS (Soccer/Tennis etc)
        elif "Soccer" in w_name or "Football" in w_name or "Tennis" in w_name:
            persona = "The Performance Analyst"
            guidelines = """
            Focus on AGILITY and WORK RATE.
            - HR Variability: Jagged graph = Good (Sprints/Rallies).
            - Fade: Did they maintain intensity?
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
        - Workout: {w_name} ({'Indoor' if is_indoor else 'Outdoor'})
        - Duration: {duration} min
        - Calories: {cals}
        - User Notes: "{logs}"
        
        DEEP METRICS (HealthKit):
        {metrics}
        
        GUIDELINES:
        {guidelines}
        
        {goal_instruction}
        
        VIDEO LIBRARY (Select One if Applicable):
        {json.dumps(VIDEO_LIBRARY, indent=2)}
        
        TASK:
        1. DEEP DIVE: Don't just summarize. Find the 'One Big Thing' they did wrong or right.
        2. USE THE DATA: Cite specific numbers from the 'DEEP METRICS' block.
           - E.g. "Your Cadence of {metrics.get('avg_cadence', 'N/A')} was too low for this pace."
        3. BE SPECIFIC: Give one actionable correction for next time.
        4. VIDEO: Select the SINGLE best URL from the library above that matches your advice. If none fit, return null.
        
        OUTPUT JSON:
        {{
            "message": "Your detailed analysis here...",
            "video_url": "https://www.youtube.com/shorts/..."
        }}
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

    # --- RECOMMENDATION TAB ---
    @observe(as_type="generation")
    def get_workout_recommendation(self, data: dict):
        """
        Daily workout recommendation engine.
        Synthesises every available signal into a single actionable prescription.
        Signals consumed:
          - CNS: HRV, RHR, orthostatic spike avg/peak BPM
          - Sleep: proxy_sleep_hours (telemetry gap), iphone_in_bed_hours
          - Recovery: heart_rate_recovery_1min, walking_asymmetry_pct
          - Long-term: vo2_max, body_mass_kg
          - Yesterday: last_workout_name, last_workout_duration_min, last_workout_calories
          - Diet: diet_rating ("nailed_it" | "minor_good" | "minor_bad" | "fully_bad")
          - Goals: active_goals (list of strings)
          - Today's food logs from Supabase
        """
        try:
            user_id = data.get("user_id")

            # Fetch today's nutrition logs for caloric context (FIXED: filter by today only)
            today_logs = []
            total_cals_today = 0
            food_summary = "No food logged yet"

            try:
                from datetime import datetime, timezone

                # Get today's date range in UTC
                now = datetime.now(timezone.utc)
                today_start = datetime(now.year, now.month, now.day, 0, 0, 0, tzinfo=timezone.utc).isoformat()
                today_end = datetime(now.year, now.month, now.day, 23, 59, 59, tzinfo=timezone.utc).isoformat()

                logs_resp = self.supabase.table("logs") \
                    .select("food_name, calories") \
                    .eq("user_id", user_id) \
                    .gte("created_at", today_start) \
                    .lte("created_at", today_end) \
                    .order("created_at", desc=True) \
                    .execute()
                today_logs = logs_resp.data

                if today_logs:
                    total_cals_today = sum([l.get("calories", 0) or 0 for l in today_logs])
                    food_summary = ", ".join([l.get("food_name", "") for l in today_logs])
            except Exception as e:
                print(f"Could not fetch logs for recommendation: {e}")

            # Pull all incoming signals with safe defaults
            hrv                    = data.get("hrv")                     # ms
            rhr                    = data.get("rhr")                     # bpm
            ortho_avg              = data.get("ortho_avg_bpm")           # bpm
            ortho_peak             = data.get("ortho_peak_bpm")          # bpm
            proxy_sleep_hours      = data.get("proxy_sleep_hours")       # hours
            iphone_in_bed_hours    = data.get("iphone_in_bed_hours")     # hours
            hrr_1min               = data.get("hrr_1min")                # bpm recovered
            walking_asymmetry_pct  = data.get("walking_asymmetry_pct")   # %
            vo2_max                = data.get("vo2_max")                 # ml/kg/min
            body_mass_kg           = data.get("body_mass_kg")            # kg
            last_workout_name      = data.get("last_workout_name", "None")
            last_workout_duration  = data.get("last_workout_duration_min", 0)
            last_workout_calories  = data.get("last_workout_calories", 0)
            today_workouts         = data.get("today_workouts", "None")
            yesterday_workouts     = data.get("yesterday_workouts", "None")
            yesterday_total_cals   = data.get("yesterday_total_calories", 0)
            diet_rating            = data.get("diet_rating", "unknown")
            active_goals           = data.get("active_goals", [])
            steps_today            = data.get("steps_today", 0)
            has_fresh_vitals       = data.get("has_fresh_vitals", False)

            # Map diet rating to human label
            diet_label_map = {
                "nailed_it":  "Nailed it (optimal fuel)",
                "minor_good": "Minor good (slightly under-fuelled)",
                "minor_bad":  "Minor bad (slightly over-indulged)",
                "fully_bad":  "Fully bad (heavily over-indulged / junk-heavy)",
                "unknown":    "Not rated yet"
            }
            diet_label = diet_label_map.get(diet_rating, "Not rated")

            # Best sleep estimate: prefer telemetry gap if available, else iPhone
            sleep_hours = proxy_sleep_hours or iphone_in_bed_hours or "Unknown"

            goals_str = "; ".join(active_goals) if active_goals else "No specific goals set"

            # Optional context from user (sleep hrs, sore knees, etc.)
            optional_context = data.get("optional_context", "")

            if optional_context:
                print(f"📝 User provided context: {optional_context}")
            else:
                print("📝 No optional context provided")

            prompt = f"""
You are an elite Athletic Performance Director making today's training prescription.
You have access to the athlete's full biometric morning audit. Be precise, direct, and decisive.
Never hedge. Give ONE clear recommendation.

=== MORNING AUDIT ===
CNS & Recovery:
  - HRV (SDNN):              {hrv} ms         [Elite >60, Good 40-60, Fatigued <40]
  - Resting HR:              {rhr} bpm         [Lower is better; spike vs personal baseline = load]
  - Orthostatic Avg HR:      {ortho_avg} bpm   [First 15 min after waking; high = CNS reactive]
  - Orthostatic Peak HR:     {ortho_peak} bpm  [>20 bpm above RHR = systemic stress flag]
  - HR Recovery (1 min):     {hrr_1min} bpm    [Elite >25 bpm drop; <12 = poor parasympathetic]

Sleep:
  - Proxy Time in Bed:       {sleep_hours} hrs [Telemetry gap method]
  - iPhone Passive inBed:    {iphone_in_bed_hours} hrs

Structural / Injury:
  - Walking Asymmetry:       {walking_asymmetry_pct}%  [>5% = hamstring/glute tightness flag]

Long-Term Capacity:
  - VO2 Max:                 {vo2_max} ml/kg/min
  - Body Mass:               {body_mass_kg} kg

=== YESTERDAY ===
  - Workouts:                {yesterday_workouts} (~{yesterday_total_cals} kcal burned)
  - Diet Rating:             {diet_label}

=== TODAY SO FAR ===
  - Workouts completed:      {today_workouts}
  - Steps:                   {steps_today}

=== ATHLETE GOALS ===
  {goals_str}

=== ATHLETE NOTES (OPTIONAL CONTEXT) ===
  {optional_context if optional_context else "None provided"}

=== YOUR TASK ===
Using ALL the signals above AND the athlete's optional notes (if any), prescribe today's training. Apply this decision logic:

1. VETO CONDITIONS (if any are true, prescribe REST or active recovery only):
   - HRV < 30 ms
   - Orthostatic peak > RHR + 25 bpm
   - Sleep < 6 hours (unless athlete manually noted different sleep hours in context)
   - Walking asymmetry > 8%
   - HRR 1-min < 10 bpm
   - Athlete mentions pain, injury, or feeling terrible in notes

2. REDUCED LOAD (if any are true, prescribe Zone 1-2 only, no intensity):
   - HRV 30-45 ms
   - Sleep 6-7.5 hours (unless athlete manually noted different sleep hours in context)
   - Diet rating = "fully_bad" OR "minor_bad"
   - Orthostatic peak > RHR + 15 bpm
   - Athlete mentions soreness, fatigue, or feeling suboptimal in notes

3. FULL SEND (all clear):
   - Sleep > 7.5 hours (ideally 8+)
   - HRV > 45 ms
   - Diet rating = "nailed_it" OR "minor_good"
   - No concerning athlete notes
   - Prescribe based on yesterday's workouts and today's completed workouts. Alternate muscle groups, allow intensity.
   - If today's workout is already complete (e.g. a walk or session done), factor that in and recommend what still makes sense for the rest of the day or tomorrow's direction.

IMPORTANT: If the athlete provides manual sleep hours in their notes (e.g., "6 hrs sleep"), use that instead of the proxy sleep estimate. If they mention specific conditions like "sore knees" or "tight hamstrings", adjust the workout accordingly (e.g., avoid high-impact, prescribe mobility work).

Output STRICT JSON:
{{
  "readiness_score": 0-100,
  "readiness_label": "High / Moderate / Low / Rest Day",
  "readiness_color": "green / yellow / orange / red",
  "recommended_workout_type": "e.g. Tempo Run / Strength / Zone 2 Ride / Rest / Yoga / HIIT",
  "recommended_duration_min": 0,
  "recommended_intensity": "Easy / Moderate / Hard / Rest",
  "headline": "One punchy sentence. E.g. 'HRV says go. Hammer a tempo run.'",
  "reasoning": "2-3 sentences citing the specific numbers that drove this decision.",
  "key_signals": [
    {{"label": "HRV", "value": "XX.X ms", "status": "good/warning/critical"}},
    {{"label": "Sleep", "value": "X.X hrs", "status": "good/warning/critical"}},
    {{"label": "Yesterday's Load", "value": "Workout name (calories burned)", "status": "good/warning/critical"}},
    {{"label": "Yesterday's Diet", "value": "{diet_label}", "status": "good/warning/critical"}},
    {{"label": "Today's Volume", "value": "Summary of today's completed workouts", "status": "good/warning/critical"}}
  ],
  "one_drill": "BEFORE YOU START: [Specific drill]. [Why it matters for today's workout]. [Exact instructions: sets, reps, duration].",
  "logic_breakdown": [
    "Paragraph 1: Your Body's State",
    "Paragraph 2: How Your Diet Helped (Or Hurt)",
    "Paragraph 3: The Logic (equation)",
    "Paragraph 4: The Prescription"
  ],
  "has_fresh_vitals": {has_fresh_vitals}
}}

CRITICAL RULES FOR key_signals:
1. MUST use EXACTLY these 5 labels in order: "HRV", "Sleep", "Yesterday's Load", "Yesterday's Diet", "Today's Volume"
2. HRV value: Show the actual number with "ms" unit (e.g. "56.8 ms")
3. Sleep value: Show the actual hours (e.g. "7.01 hrs" or "Unknown")
4. Yesterday's Load value: Show yesterday's workout summary from the data above (e.g. "Strength 30min (200 kcal)" or "Rest Day")
5. Yesterday's Diet value: MUST be exactly one of: "Nailed it", "Minor good", "Minor bad", "Fully bad", or "Not rated yet"
6. Today's Volume value: Show today's completed workouts ONLY, excluding diet/food (e.g. "2 Strength Sessions" or "Rest Day")
7. Status rules:
   - "good" = green checkmark (optimal)
   - "warning" = yellow triangle (moderate concern)
   - "critical" = red X (requires attention/veto trigger)

CRITICAL RULES FOR logic_breakdown:
This is the MOST IMPORTANT section — it must tell a compelling STORY, not list data.

FORMAT (exactly 4 paragraphs):

Paragraph 1 — "YOUR BODY'S STATE" (current recovery status):
- Start with an analogy that explains the athlete's recovery state (e.g., "Your body is in high-performance mode" or "Your body is in debt collection mode")
- Explain EACH key signal using relatable comparisons:
  * HRV: Battery percentage (low = low charge), nervous system capacity
  * RHR: Engine temperature (high = running hot, still processing load)
  * Sleep: Phone charging overnight (missing/low = didn't charge properly)
  * Yesterday's load: Recent withdrawals from the recovery bank
  * Today's volume: Already spent energy today
- Use conversational language: "think of it like...", "it's like...", "imagine..."
- Make it personal: "Your nervous system...", "Your body..."

Paragraph 2 — "HOW YOUR DIET HELPED (OR HURT)" (diet impact analysis):
MANDATORY: You MUST explain the diet's role in unlocking or limiting today's capacity.
- If diet = "nailed_it": Explain how good nutrition ENABLED this workout capacity
  * Example: "Because you nailed your diet yesterday, your glycogen stores are fully topped up — like filling your car's gas tank to 100%. This gives you the fuel to train hard today without crashing mid-session."
  * Show the counterfactual: "If you'd eaten poorly, you'd be running on fumes right now, forcing a reduced-load day even with good HRV."
- If diet = "minor_good": Show what was unlocked and what's still limited
  * Example: "Your decent diet yesterday provided enough fuel for moderate work, but not enough to go all-out. You're at 70% tank capacity."
- If diet = "minor_bad": Explain the penalty
  * Example: "Yesterday's diet mistakes are costing you today. Poor nutrition increases inflammation (hence elevated RHR) and limits glycogen availability. You could have done intervals today, but now you're capped at Zone 2."
- If diet = "fully_bad": Drive home the impact
  * Example: "Yesterday's diet disaster is the main reason we're prescribing rest today. Junk food spikes cortisol, disrupts sleep quality, and drains recovery capacity. Even if HRV was good, bad diet would still force caution."
ALWAYS include: "This is why nutrition compliance unlocks performance — it's not just about calories, it's about earning tomorrow's workout capacity."

Paragraph 3 — "THE LOGIC" (how signals combine):
- Show the EQUATION: How the signals combine to create the decision
- Example: "Good HRV + Good Sleep + Nailed Diet + Rest yesterday = Full send clearance"
- Or: "Low HRV + Poor Sleep + Bad Diet = Triple veto, recovery mandatory"
- Explain the consequence clearly
- Connect it to the decision rules (veto/reduced/full-send)

Paragraph 4 — "THE PRESCRIPTION" (what to do and why):
- State the recommendation clearly
- Explain WHY this specific workout type/intensity makes sense given the state
- If diet was good: Celebrate what it unlocked ("Your discipline yesterday earned you this session")
- If diet was bad: Show the path back ("Fix tonight's diet to unlock tomorrow's capacity")
- Give forward guidance: what this achieves

EXAMPLES OF GOOD ANALOGIES:
- HRV 30ms: "Like your phone at 15% battery — it works, but any heavy app will crash it"
- RHR elevated: "Your engine is idling hot, still processing yesterday's workload"
- Sleep missing: "Like trying to charge your phone with a faulty cable — you don't know if it actually charged"
- Already trained today on low HRV: "Like driving on a spare tire — you've used up your safety margin"
- High volume yesterday: "You made a big withdrawal from the recovery bank yesterday"

IMPORTANT:
- Do NOT list steps (no "Step 1, Step 2...")
- Do NOT repeat data from the reasoning field
- Do NOT use technical jargon without explaining it
- DO use relatable analogies for every metric
- DO connect the dots between signals
- DO write in second person ("Your body", not "The athlete's body")
- MANDATORY: Paragraph 2 MUST discuss diet impact (even if diet = "unknown", explain what's missing)
- MANDATORY: Include counterfactual reasoning ("If you'd eaten poorly, you'd be..." or "If you'd eaten better, you could...")
- Each paragraph should be 3-5 sentences
- Total length: ~300-350 words across all 4 paragraphs

CRITICAL RULES FOR one_drill:
This is a PRE-WORKOUT activation drill that must be completed BEFORE the main workout.
The drill MUST be specific to today's prescription and body state.

FORMAT (3 parts in one string):
1. START WITH URGENCY: "BEFORE YOU START: [Drill name]"
2. WHY IT MATTERS: One sentence explaining how this drill prepares the body for today's specific workout
3. EXACT INSTRUCTIONS: Precise protocol (sets, reps, duration, focus)

EXAMPLES:

For Tempo Run after strength yesterday:
"BEFORE YOU START: Hip Flexor + Glute Activation Circuit. Yesterday's strength work left your hips tight, which will limit your stride and spike injury risk on today's tempo run. Do 2 rounds: 10 walking lunges per leg (focus on depth), 10 glute bridges (squeeze at top for 2 seconds), 30-second pigeon pose each side."

For Strength after poor sleep:
"BEFORE YOU START: CNS Wake-Up Drill. Your low HRV means your nervous system isn't firing at full capacity, which reduces power output and coordination for heavy lifts. Do 3 sets: 5 jump squats (land soft), 10 fast push-ups (explosive), 10 med ball slams. This primes your CNS without fatiguing you."

For Zone 2 Run (recovery day):
"BEFORE YOU START: Dynamic Mobility Flow. Your body is in recovery mode, so we need to wake up stiff joints without adding load. Do 1 round: 10 leg swings each direction, 10 arm circles forward/back, 10 cat-cows, 5 world's greatest stretch each side. Total time: 3-4 minutes."

For Rest Day:
"BEFORE YOU START: Not applicable — today is full rest. If you feel restless, a 10-minute easy walk is fine, but no formal activation needed."

RULES:
- Always start with "BEFORE YOU START:"
- Be SPECIFIC (no generic "warm up")
- Explain WHY based on today's body state (HRV, yesterday's workout, etc.)
- Give EXACT protocol (no vague "do some stretches")
- Keep total time under 5 minutes
- Tailor to the workout type (running vs strength vs HIIT need different prep)
"""
            response = self.model.generate_content(prompt)
            clean = response.text.replace("```json", "").replace("```", "").strip()
            return clean

        except Exception as e:
            import json
            return json.dumps({"headline": f"Error generating recommendation: {str(e)}", "readiness_score": 0})

    # --- TOMORROW PREVIEW ---
    @observe(as_type="generation")
    def get_tomorrow_preview(self, data: dict):
        """
        Lightweight next-day soft preview.
        Triggered immediately when the user saves their diet rating for today.
        Inputs: today's workout (name, duration, calories) + diet rating only.
        No HealthKit, no goals — those are folded in during the morning finalisation.
        Returns a soft preview with a clear caveat that it will be updated in the morning.
        """
        try:
            today_workouts        = data.get("today_workouts", "None")
            today_total_calories  = data.get("today_total_calories", 0)
            diet_rating           = data.get("diet_rating", "unknown")

            diet_label_map = {
                "nailed_it":  "Nailed it (optimal fuel — full recovery likely)",
                "minor_good": "Minor good (slightly under-fuelled — moderate recovery)",
                "minor_bad":  "Minor bad (slightly over-indulged — some inflammation likely)",
                "fully_bad":  "Fully bad (heavy junk / overeating — recovery compromised)",
                "unknown":    "Not rated"
            }
            diet_label = diet_label_map.get(diet_rating, "Not rated")

            prompt = f"""
You are an Athletic Performance Director giving TOMORROW'S PREVIEW after the user rates their diet.
This is shown in the evening (after today's work is done) to preview tomorrow's likely workout.
Be CONFIDENT and MOTIVATING. The goal is to make them excited about tomorrow AND motivated to sleep/recover well tonight.

=== TODAY'S DATA ===
Workouts completed: {today_workouts} (~{today_total_calories} kcal burned)
Diet rating:        {diet_label}

=== YOUR TASK ===
Analyze today's training load + diet quality to preview tomorrow's workout.

DECISION LOGIC:
1. What muscle groups / energy systems were taxed today?
   - Strength → suggest cardio/mobility tomorrow (alternate)
   - Running → suggest strength or rest tomorrow (alternate)
   - HIIT → suggest Zone 2 or rest tomorrow (recover)
   - Rest today → suggest any moderate session tomorrow

2. How does diet impact tomorrow's capacity?
   - "Nailed it" → Full capacity unlocked, can go hard
   - "Minor good" → Moderate capacity, cap at moderate intensity
   - "Minor bad" → Reduced capacity, cap at easy/Zone 2
   - "Fully bad" → Minimal capacity, likely rest or very light work

3. Create a CONFIDENT preview (not "we're likely looking at..." but "Tomorrow: [X]")

Output STRICT JSON:
{{
  "preview_workout_type": "EXACT workout type: e.g. 'Zone 2 Run' / 'Upper Body Strength' / 'Mobility Flow' / 'Rest Day'",
  "preview_duration_range": "EXACT duration: e.g. '35 min' (provide single number, not range)",
  "preview_intensity_ceiling": "EXACT intensity: 'Easy' / 'Moderate' / 'Hard'",
  "preview_headline": "CONFIDENT one-liner that builds excitement. E.g. 'Tomorrow: Upper body strength — your legs earned a break.' or 'Tomorrow: Easy Zone 2 run to flush yesterday's damage.'",
  "preview_reasoning": "2-3 sentences. First: explain what today taxed. Second: explain how diet unlocked (or limited) tomorrow. Third (optional): motivate good sleep/recovery tonight.",
  "preview_exact_prescription": "Detailed workout breakdown with sets/reps/pace. E.g. '4 x 8min at Zone 2 (130-145 bpm), 2min walk rest between sets' OR '4 sets: Bench Press 8-10 reps, Rows 10-12 reps, Shoulder Press 8-10 reps, rest 90sec'",
  "caveat": "Morning HRV and sleep will fine-tune this plan if needed."
}}

EXAMPLES:

After heavy strength + good diet:
{{
  "preview_headline": "Tomorrow: Zone 2 cardio to flush the lactic acid and keep momentum.",
  "preview_reasoning": "Today's strength session taxed your muscular system hard (448 kcal burned). Because you nailed your diet, your glycogen is topped up for tomorrow's work. Get 8+ hours of sleep tonight to lock in those gains and clear tomorrow for cardio.",
  "preview_workout_type": "Zone 2 Run",
  "preview_duration_range": "40 min",
  "preview_intensity_ceiling": "Moderate",
  "preview_exact_prescription": "40 min continuous run. Target HR: 130-145 bpm (Zone 2). Pace: conversational (should be able to talk easily). No intervals, keep it steady. Focus on nose breathing if possible.",
  "caveat": "Morning HRV and sleep will fine-tune this plan if needed."
}}

After light run + bad diet:
{{
  "preview_headline": "Tomorrow: Light mobility flow — tonight's diet limited your options.",
  "preview_reasoning": "Today's run was moderate (300 kcal), so your legs could handle more tomorrow. But your poor diet choice compromised recovery capacity — inflammation will be elevated and fuel stores are compromised. Fix tonight's meal and sleep to unlock a real session the day after.",
  "preview_workout_type": "Mobility & Stretching",
  "preview_duration_range": "20 min",
  "preview_intensity_ceiling": "Easy",
  "preview_exact_prescription": "20 min flow: 5min dynamic warmup (leg swings, arm circles), 10min yoga sequence (downward dog, pigeon pose, hip flexor stretches), 5min breathing work. Keep heart rate below 100 bpm.",
  "caveat": "Morning HRV and sleep will fine-tune this plan if needed."
}}

After rest day + good diet:
{{
  "preview_headline": "Tomorrow: You're fueled and rested — time to attack a hard session.",
  "preview_reasoning": "You rested today and nailed your diet, which means your recovery tank is full. Tomorrow is your chance to capitalize on this readiness with intensity. Prioritize sleep tonight to confirm green lights across the board.",
  "preview_workout_type": "Tempo Run",
  "preview_duration_range": "45 min",
  "preview_intensity_ceiling": "Hard",
  "preview_exact_prescription": "10min easy warmup, 25min tempo at Zone 3-4 (150-165 bpm, comfortably hard pace), 10min easy cooldown. Target: sustain tempo pace, not sprint intervals.",
  "caveat": "Morning HRV and sleep will fine-tune this plan if needed."
}}

RULES:
- Be CONFIDENT, not wishy-washy ("Tomorrow: X" not "We're likely looking at X")
- Make it MOTIVATING (build excitement for tomorrow)
- Connect diet directly to tomorrow's capacity (show cause → effect)
- If diet was good: celebrate and motivate ("You earned this")
- If diet was bad: show consequence and path forward ("Fix tonight to unlock the day after")
- Always end reasoning with a forward-looking statement (sleep, next meal, etc.)
"""
            response = self.model.generate_content(prompt)
            clean = response.text.replace("```json", "").replace("```", "").strip()
            return clean

        except Exception as e:
            import json
            return json.dumps({
                "preview_headline": f"Preview unavailable: {str(e)}",
                "preview_workout_type": "Unknown",
                "preview_duration_range": "--",
                "preview_intensity_ceiling": "--",
                "preview_reasoning": "",
                "caveat": "Morning audit will finalise your recommendation."
            })

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

    # --- PHASE 6.3: CONTEXTUAL CHAT ---
    @observe(as_type="generation")
    def chat_with_coach(self, data: dict):
        """
        Maintains a persona-driven conversation about a specific workout.
        """
        try:
            metrics = data.get("metrics", {})
            history = data.get("history", []) # List of {role:user/model, text:msg}
            w_name = metrics.get("workout_name", "Workout")

            # Determine Persona (Reuse Logic)
            is_indoor = metrics.get("is_indoor", False)
            persona = "General Coach"
            if "Running" in w_name:
                 if is_indoor: persona = "The Pacer (Indoor Run Specialist)"
                 else: persona = "The Biomechanist (Olympic Running Coach)"
            elif "Strength" in w_name: persona = "The Hypertrophy Expert"
            elif "HIIT" in w_name: persona = "The Metabolic Coach"
            elif "Cycling" in w_name: persona = "The Tour Directuer"
            elif "Swimming" in w_name: persona = "The Aquatics Director"
            elif "Soccer" in w_name or "Football" in w_name: persona = "The Performance Analyst"

            # Construct Conversation History
            conversation_text = ""
            for msg in history:
                role = msg.get("role", "user").upper()
                text = msg.get("text", "")
                conversation_text += f"{role}: {text}\n"

            # Final Prompt (Stateless)
            final_prompt = f"""
            You are {persona}.
            You are chatting with an athlete about their recent {w_name} session.

            CONTEXT (Workout Data):
            {json.dumps(metrics, indent=2)}

            INSTRUCTIONS:
            - Keep answers short (under 3 sentences), punchy, and motivating.
            - Use the specific metrics provided above to back up your points.
            - If they ask "How do I fix X?", give a specific drill.
            - Call them 'Athlete'.

            CONVERSATION SO FAR:
            {conversation_text}

            (You are replying to the last USER message above. Do NOT use markdown. Just plain text.)
            YOUR RESPONSE:
            """

            response = self.model.generate_content(final_prompt)
            return json.dumps({"message": response.text})

        except Exception as e:
            return json.dumps({"message": f"I am having trouble replying. ({str(e)})"})

    # --- GLOBAL COACH CHAT (All Workouts) ---
    @observe(as_type="generation")
    def chat_with_coach_global(self, data: dict):
        """
        Maintains a conversation about the user's overall training (configurable days).
        Persona: Performance Director / Holistic Coach with full recovery, nutrition, and goals context
        """
        try:
            user_id = data.get("user_id")
            history = data.get("history", [])
            summary = data.get("workouts_summary", {})
            days = data.get("days", 30)  # Get dynamic time range, default to 30

            print(f"🎯 Global Coach: Analyzing {days} days of data")

            # Extract key metrics for easier access
            weekly_summary = summary.get("weekly_summary", [])
            trends = summary.get("trends", {})
            recovery = summary.get("recovery_summary", {})
            nutrition = summary.get("nutrition_summary", {})
            goals = summary.get("active_goals", [])
            total_workouts = summary.get("total_workouts", 0)
            rest_days = summary.get("total_rest_days", 0)

            # Construct Conversation History
            conversation_text = ""
            for msg in history:
                role = msg.get("role", "user").upper()
                text = msg.get("text", "")
                conversation_text += f"{role}: {text}\n"

            # Enhanced Prompt with comprehensive data
            time_range_label = f"Last {days} day{'s' if days != 1 else ''}"
            final_prompt = f"""
            You are an Elite Performance Director with {days} day{'s' if days != 1 else ''} of holistic athlete data.

            ATHLETE PROFILE ({time_range_label}):
            Period: {summary.get("period", time_range_label)}
            Total Workouts: {total_workouts}
            Rest Days: {rest_days}

            WEEKLY BREAKDOWN:
            {json.dumps(weekly_summary, indent=2)}

            WORKOUT TYPE DISTRIBUTION:
            {json.dumps(summary.get("workout_type_summary", []), indent=2)}

            TRENDS:
            - Volume: {trends.get("volume_trend", "unknown")}
            - HRV: {trends.get("hrv_trend", "unknown")}

            RECOVERY METRICS:
            - Average HRV: {recovery.get("avg_hrv_30d", 0):.1f} ms (over {days} days)
            - Average Sleep: {recovery.get("avg_sleep_hours", 0):.1f} hours/night (over {days} days)

            NUTRITION:
            - Avg Daily Calories: {nutrition.get("avg_daily_calories", 0)}
            - Total Food Logs: {nutrition.get("total_logs", 0)}

            ACTIVE GOALS:
            {json.dumps(goals, indent=2) if goals else "None set"}

            YOUR CAPABILITIES AS PERFORMANCE DIRECTOR:
            1. Volume Management:
               - Flag if training load is increasing too fast (>20% week-over-week = injury risk)
               - Assess if volume is appropriate for goals
               - Identify if athlete is under-training

            2. Recovery Analysis:
               - Use HRV trends to detect overtraining (declining HRV = stress accumulation)
               - Correlate sleep quality with performance
               - Recommend deload weeks if recovery is poor

            3. Progression Tracking:
               - Compare metrics across the time period ({"daily" if days == 1 else "weekly" if days == 7 else "Week 1 vs Week 4"} trends)
               - Identify if athlete is improving, plateauing, or regressing
               - Check if progression aligns with goals

            4. Injury Risk Assessment:
               - Watch for volume spikes (>20% increase)
               - Monitor rest day frequency (need 1-2 per week minimum)
               - Flag if HRV is declining despite rest

            5. Goal Alignment:
               - Assess if current training supports stated goals
               - Recommend adjustments if off-track
               - Calculate days remaining until goal dates

            6. Nutrition-Performance Correlation:
               - If nutrition logs exist, correlate calorie intake with performance
               - Flag under-fueling if workouts are high but calories are low

            INSTRUCTIONS:
            - Give MACRO-level insights (not workout-by-workout details unless asked)
            - Always cite specific numbers from the data
            - For {days}-day analysis: {"focus on today's performance" if days == 1 else "compare weekly trends" if days == 7 else "compare Week 1 vs Week 4 metrics"}
            - When comparing periods, use exact values from weekly_summary
            - If HRV is declining AND volume is increasing, warn about overtraining
            - If volume increased >20% between any two consecutive periods, flag injury risk
            - If sleep is <7 hours on average, recommend prioritizing rest
            - If goals are set, reference days remaining and whether current pace is on-track
            - Be direct, data-driven, and motivating but honest
            - Keep answers under 5 sentences (6 if explaining complex trends)
            - Call them 'Athlete'

            CONVERSATION SO FAR:
            {conversation_text}

            (You are replying to the last USER message above. Do NOT use markdown. Just plain text.)
            YOUR RESPONSE:
            """

            response = self.model.generate_content(final_prompt)
            return json.dumps({"message": response.text})

        except Exception as e:
            return json.dumps({"message": f"I am having trouble replying. ({str(e)})"})

    # --- PREVIEW COACH CHAT (Tomorrow's Preview) ---
    @observe(as_type="generation")
    def chat_with_coach_preview(self, data: dict):
        """
        Maintains a conversation about tomorrow's workout preview (evening).
        Persona: Planning Coach
        """
        try:
            user_id = data.get("user_id")
            history = data.get("history", [])
            preview = data.get("preview", {})
            today_workouts = data.get("today_workouts", "None")
            diet_rating = data.get("diet_rating", "unknown")

            # Construct Conversation History
            conversation_text = ""
            for msg in history:
                role = msg.get("role", "user").upper()
                text = msg.get("text", "")
                conversation_text += f"{role}: {text}\n"

            # Final Prompt
            final_prompt = f"""
            You are a Planning Coach discussing tomorrow's workout preview with an athlete (evening chat).

            CONTEXT:
            - Today's Workouts: {today_workouts}
            - Today's Diet Rating: {diet_rating}
            - Tomorrow's Preview: {json.dumps(preview, indent=2)}

            INSTRUCTIONS:
            - This is a SOFT PREVIEW based on today's data only
            - Final plan will be confirmed tomorrow morning with HRV, sleep, and recovery data
            - Answer questions like "Can I do HIIT instead?", "Why rest?", "What if I eat better tonight?"
            - Explain how tonight's sleep and recovery will impact tomorrow's final plan
            - If they want to change intensity, explain what needs to happen tonight (sleep, nutrition)
            - Be honest: "This is a preview - your body tomorrow will have the final say"
            - Keep answers under 4 sentences
            - Call them 'Athlete'

            CONVERSATION SO FAR:
            {conversation_text}

            (You are replying to the last USER message above. Do NOT use markdown. Just plain text.)
            YOUR RESPONSE:
            """

            response = self.model.generate_content(final_prompt)
            return json.dumps({"message": response.text})

        except Exception as e:
            return json.dumps({"message": f"I am having trouble replying. ({str(e)})"})

    # --- RECOMMENDATION COACH CHAT (Morning Recommendation) ---
    @observe(as_type="generation")
    def chat_with_coach_recommendation(self, data: dict):
        """
        Maintains a conversation about the final morning workout recommendation.
        Persona: Performance Director with full vitals access
        """
        try:
            user_id = data.get("user_id")
            history = data.get("history", [])
            recommendation = data.get("recommendation", {})

            # Construct Conversation History
            conversation_text = ""
            for msg in history:
                role = msg.get("role", "user").upper()
                text = msg.get("text", "")
                conversation_text += f"{role}: {text}\n"

            # Final Prompt
            final_prompt = f"""
            You are an Elite Performance Director with full access to the athlete's morning vitals.

            MORNING RECOMMENDATION:
            {json.dumps(recommendation, indent=2)}

            INSTRUCTIONS:
            - This is the FINAL recommendation based on HRV, sleep, HR, recovery metrics
            - Answer questions like "Can I push harder?", "Why is my HRV low?", "Explain the drill"
            - Use specific numbers from the recommendation (HRV, sleep hours, readiness score, etc.)
            - If they want to override the recommendation, explain the risks based on their current state
            - If they ask about the drill, break it down step-by-step
            - Be authoritative but supportive - you have the data to back up your decisions
            - Keep answers under 4 sentences unless explaining a drill (then use 5-6)
            - Call them 'Athlete'

            CONVERSATION SO FAR:
            {conversation_text}

            (You are replying to the last USER message above. Do NOT use markdown. Just plain text.)
            YOUR RESPONSE:
            """

            response = self.model.generate_content(final_prompt)
            return json.dumps({"message": response.text})

        except Exception as e:
            return json.dumps({"message": f"I am having trouble replying. ({str(e)})"})

    # ==================== MCP INTEGRATION: GROCERY & FOOD ORDERING ====================

    @observe(as_type="generation")
    def search_groceries_mcp(self, data: dict):
        """
        Search for groceries across MCP services (Swiggy Instamart, Zepto).

        Request body:
        {
            "user_id": "...",
            "query": "chicken breast",
            "service": "swiggy_instamart" (optional, default: search all)
        }
        """
        try:
            if not self.grocery_tools:
                return json.dumps({"error": "MCP tools not available"})

            query = data.get('query', '')
            service = data.get('service')

            if not query:
                return json.dumps({"error": "Missing 'query' parameter"})

            # Search across all services or specific service
            if service:
                results = self.grocery_tools.search_groceries(query, service=service)
            else:
                # Search all and compare
                results = self.grocery_tools.compare_prices(query)

            return json.dumps({
                "query": query,
                "results": results,
                "count": len(results)
            })

        except Exception as e:
            return json.dumps({"error": str(e)})

    @observe(as_type="generation")
    def compare_prices_mcp(self, data: dict):
        """
        Compare prices of an item across all services.

        Request body:
        {
            "user_id": "...",
            "query": "brown rice 1kg"
        }
        """
        try:
            if not self.grocery_tools:
                return json.dumps({"error": "MCP tools not available"})

            query = data.get('query', '')
            if not query:
                return json.dumps({"error": "Missing 'query' parameter"})

            results = self.grocery_tools.compare_prices(query)

            # Find cheapest
            cheapest = results[0] if results else None

            return json.dumps({
                "query": query,
                "all_options": results,
                "cheapest": cheapest,
                "savings": results[0]['price'] - results[-1]['price'] if len(results) > 1 else 0
            })

        except Exception as e:
            return json.dumps({"error": str(e)})

    @observe(as_type="generation")
    def suggest_protein_sources_mcp(self, data: dict):
        """
        AI-powered protein source suggestions based on budget and goals.

        Request body:
        {
            "user_id": "...",
            "budget": 500,
            "goal_protein_g": 150
        }
        """
        try:
            if not self.grocery_tools:
                return json.dumps({"error": "MCP tools not available"})

            budget = float(data.get('budget', 500))
            goal_protein = float(data.get('goal_protein_g', 150))

            suggestions = self.grocery_tools.suggest_protein_sources(
                budget=budget,
                goal_protein_g=goal_protein
            )

            total_cost = sum(item['price'] for item in suggestions)
            total_protein = sum(item.get('nutrition', {}).get('protein_g', 0) for item in suggestions)

            return json.dumps({
                "suggestions": suggestions,
                "total_cost": total_cost,
                "total_protein": total_protein,
                "goal_protein": goal_protein,
                "budget": budget,
                "budget_remaining": budget - total_cost
            })

        except Exception as e:
            return json.dumps({"error": str(e)})

    @observe(as_type="generation")
    def smart_order_from_prompt_mcp(self, data: dict):
        """
        AI-powered natural language food ordering.

        Example prompts:
        - "Order 500g chicken breast from cheapest source"
        - "Get me post-workout meal ingredients under ₹300"
        - "Order groceries for high protein breakfast"

        Request body:
        {
            "user_id": "...",
            "prompt": "Order chicken breast and eggs"
        }
        """
        try:
            if not self.grocery_tools:
                return json.dumps({"error": "MCP tools not available"})

            user_id = data.get('user_id')
            prompt = data.get('prompt', '')

            if not prompt:
                return json.dumps({"error": "Missing 'prompt' parameter"})

            # Use Gemini to parse the prompt
            parse_prompt = f"""
            You are a nutrition-aware shopping assistant. Parse this user request:
            "{prompt}"

            Extract:
            1. Items they want (e.g., ["chicken breast", "eggs", "brown rice"])
            2. Budget constraint (if mentioned)
            3. Nutrition goals (e.g., high protein, low carb)
            4. Quantity preferences

            Output JSON:
            {{
                "items": ["item1", "item2"],
                "budget": 500,
                "nutrition_goal": "high_protein",
                "quantities": {{"chicken breast": "500g"}}
            }}
            """

            response = self.model.generate_content(parse_prompt)
            parsed = json.loads(response.text)

            # Search for each item and find best options
            shopping_list = []
            total_cost = 0

            for item in parsed.get('items', []):
                # Compare prices across services
                options = self.grocery_tools.compare_prices(item)

                if options:
                    # Pick cheapest or best nutrition match
                    best_option = options[0]
                    shopping_list.append(best_option)
                    total_cost += best_option['price']

            return json.dumps({
                "original_prompt": prompt,
                "parsed_intent": parsed,
                "shopping_list": shopping_list,
                "total_cost": total_cost,
                "ready_to_order": True
            })

        except Exception as e:
            return json.dumps({"error": str(e)})

    @observe(as_type="generation")
    def search_restaurants_mcp(self, data: dict):
        """
        Search for restaurants via Zomato/Swiggy Food MCP.

        Request body:
        {
            "user_id": "...",
            "lat": 12.9716,
            "lng": 77.5946,
            "cuisine": "North Indian" (optional)
        }
        """
        try:
            if not self.grocery_tools:
                return json.dumps({"error": "MCP tools not available"})

            lat = data.get('lat')
            lng = data.get('lng')
            cuisine = data.get('cuisine')
            service = data.get('service', 'zomato')

            location = {'lat': lat, 'lng': lng} if lat and lng else None

            restaurants = self.grocery_tools.search_restaurants(
                location=location,
                cuisine=cuisine,
                service=service
            )

            return json.dumps({
                "restaurants": restaurants,
                "count": len(restaurants),
                "location": location,
                "cuisine": cuisine
            })

        except Exception as e:
            return json.dumps({"error": str(e)})

    @observe(as_type="generation")
    def get_menu_mcp(self, data: dict):
        """
        Get restaurant menu with nutrition info.

        Request body:
        {
            "user_id": "...",
            "restaurant_id": "...",
            "service": "zomato"
        }
        """
        try:
            if not self.grocery_tools:
                return json.dumps({"error": "MCP tools not available"})

            restaurant_id = data.get('restaurant_id')
            service = data.get('service', 'zomato')

            if not restaurant_id:
                return json.dumps({"error": "Missing 'restaurant_id' parameter"})

            menu = self.grocery_tools.get_menu(restaurant_id, service=service)

            return json.dumps({
                "restaurant_id": restaurant_id,
                "menu": menu,
                "count": len(menu)
            })

        except Exception as e:
            return json.dumps({"error": str(e)})

    @observe(as_type="generation")
    def analyze_equipment(self, data):
        """
        Analyzes gym equipment from image/video using Gemini Vision Pro.
        Stores result in users.equipment_access JSONB.
        Uploads media to gym_media bucket using user's gym_media_url path.
        """
        from langfuse.decorators import langfuse_context
        import base64
        import uuid
        from datetime import datetime

        try:
            user_id = data.get('user_id')
            media_data = data.get('image_data') or data.get('video_data')
            mime_type = data.get('mime_type', 'image/jpeg')

            if not user_id or not media_data:
                return json.dumps({"error": "Missing user_id or media_data", "success": False, "message": "Missing required parameters"})

            # 1. Get or set user's gym_media_url (folder path in bucket)
            user_response = self.supabase.table("users").select("gym_media_url, equipment_access").eq("id", user_id).execute()

            if not user_response.data:
                return json.dumps({"error": "User not found", "success": False, "message": "User does not exist in database"})

            user_data = user_response.data[0]
            gym_media_path = user_data.get('gym_media_url')

            # Initialize gym_media_url if not set
            if not gym_media_path:
                gym_media_path = f"{user_id}/"
                self.supabase.table("users").update({"gym_media_url": gym_media_path}).eq("id", user_id).execute()

            # 2. Upload media to gym_media bucket
            media_bytes = base64.b64decode(media_data)
            file_extension = 'jpg' if 'image' in mime_type else 'mp4'
            filename = f"{uuid.uuid4()}.{file_extension}"
            full_path = f"{gym_media_path}{filename}"  # e.g., "user_id/abc-123.jpg"

            # Upload to gym_media bucket
            try:
                storage_response = self.supabase.storage.from_('gym_media').upload(
                    full_path,
                    media_bytes,
                    {'content-type': mime_type}
                )
                print(f"📤 Uploaded to storage: {full_path}")
            except Exception as upload_error:
                print(f"❌ Storage upload error: {upload_error}")
                return json.dumps({"error": f"Storage upload failed: {str(upload_error)}", "success": False, "message": "Failed to upload media"})

            # Get public URL and clean it
            media_url = self.supabase.storage.from_('gym_media').get_public_url(full_path)

            # Remove trailing query parameters if any
            if '?' in media_url and media_url.endswith('?'):
                media_url = media_url.rstrip('?')

            print(f"🔗 Generated media URL: {media_url}")

            # 3. Analyze with Gemini Vision Pro
            system_prompt = """
You are an expert gym equipment analyzer. Analyze this image/video and identify EACH INDIVIDUAL piece of equipment separately.

CRITICAL INSTRUCTIONS:
- Count and list EACH item individually - do NOT group identical items together
- For resistance bands: Look carefully at COLOR, THICKNESS, and any printed text/markings
  * Different colors usually mean different resistance levels (e.g., red=light, black=medium, blue=heavy)
  * List each band separately with its unique characteristics
  * Common colors: Yellow (lightest), Red (light), Green (medium), Blue (heavy), Black (extra heavy)
- For dumbbells/weights: Note the EXACT weight if visible (look for numbers printed on them)
- For multiple similar items: Create separate entries for EACH one with their specific details
- Be specific about brands/models if visible on the equipment
- Note condition: new, used, worn, damaged

IDENTIFICATION CHECKLIST:
1. Count total number of distinct items
2. Examine each item for unique characteristics (color, size, markings, weight)
3. Create ONE entry per physical item (not per category)
4. In "details" field, describe what makes this item unique

EQUIPMENT TYPES:
- "cardio": treadmill, bike, rower, elliptical
- "strength": cable machines, smith machine, power rack
- "free_weights": dumbbells, barbells, kettlebells, weight plates
- "machine": leg press, chest press, lat pulldown
- "accessory": resistance bands, yoga mat, foam roller, pull-up bar, ab wheel
- "bench": flat bench, adjustable bench, decline bench

ENVIRONMENT:
- "home_gym": residential setting, limited equipment
- "commercial_gym": gym facility with extensive equipment
- "outdoor": park, outdoor fitness area
- "apartment": compact space, minimal equipment

OUTPUT STRICT JSON ONLY (no markdown, no code blocks):
{
    "equipment": [
        {
            "name": "Specific equipment name",
            "type": "cardio|strength|free_weights|machine|accessory|bench",
            "quantity": "1",
            "details": "Exact color, resistance level/weight, brand, unique markings, condition",
            "confidence": "high|medium|low"
        }
    ],
    "environment": "home_gym|commercial_gym|outdoor|apartment",
    "total_items": <count of individual items>
}

EXAMPLE for 3 resistance bands:
{
    "equipment": [
        {"name": "Resistance Band", "type": "accessory", "quantity": "1", "details": "Red color, light resistance (15 lbs equivalent), fabric loop style", "confidence": "high"},
        {"name": "Resistance Band", "type": "accessory", "quantity": "1", "details": "Blue color, heavy resistance (25 lbs equivalent), fabric loop style", "confidence": "high"},
        {"name": "Resistance Band", "type": "accessory", "quantity": "1", "details": "Black color, extra heavy resistance (35 lbs equivalent), fabric loop style", "confidence": "high"}
    ],
    "environment": "home_gym",
    "total_items": 3
}
"""

            # Create multimodal request
            media_part = Part.from_data(
                data=base64.b64decode(media_data),
                mime_type=mime_type
            )

            response = self.model.generate_content([
                system_prompt,
                "Analyze this gym equipment image/video:",
                media_part
            ])

            # Parse Gemini response (handle markdown code blocks if present)
            response_text = response.text.strip()
            if response_text.startswith('```'):
                # Remove markdown code blocks
                response_text = response_text.split('```')[1]
                if response_text.startswith('json'):
                    response_text = response_text[4:]
                response_text = response_text.strip()

            equipment_data = json.loads(response_text)

            # 4. Get existing equipment_access
            existing_equipment = user_data.get('equipment_access', [])
            if not isinstance(existing_equipment, list):
                existing_equipment = []

            # 5. Create new submission entry with validation
            equipment_list = equipment_data.get('equipment', [])
            environment_value = equipment_data.get('environment', 'unknown')

            # Ensure environment is never null
            if environment_value is None or environment_value == "":
                environment_value = "unknown"

            new_submission = {
                "id": str(uuid.uuid4()),
                "timestamp": datetime.utcnow().isoformat(),
                "media_url": media_url,
                "media_type": "image" if 'image' in mime_type else "video",
                "filename": filename,
                "equipment": equipment_list if isinstance(equipment_list, list) else [],
                "environment": environment_value,
                "total_items": equipment_data.get('total_items', len(equipment_list) if isinstance(equipment_list, list) else 0)
            }

            # 6. Append to existing array
            existing_equipment.append(new_submission)

            # 7. Update users.equipment_access (keep last 100 submissions)
            updated_equipment = existing_equipment[-100:]

            self.supabase.table("users").update({
                "equipment_access": updated_equipment
            }).eq("id", user_id).execute()

            # Log to Langfuse
            langfuse_context.update_current_trace(
                user_id=user_id,
                tags=["equipment_analysis"],
                metadata={
                    "equipment_count": len(equipment_data.get('equipment', [])),
                    "environment": equipment_data.get('environment'),
                    "media_type": "image" if 'image' in mime_type else "video"
                }
            )

            print(f"✅ Equipment analyzed for user {user_id}: {len(equipment_data.get('equipment', []))} items")

            return json.dumps({
                "success": True,
                "message": f"Analyzed {len(equipment_data.get('equipment', []))} equipment items!",
                "submission": new_submission
            })

        except Exception as e:
            print(f"❌ Error analyzing equipment: {e}")
            import traceback
            traceback.print_exc()
            return json.dumps({"error": str(e), "success": False})

    def get_equipment_history(self, data):
        """
        Fetches user's equipment submission history from equipment_access JSONB.
        Returns in reverse chronological order (newest first).
        """
        try:
            user_id = data.get('user_id')
            if not user_id:
                return json.dumps({"error": "Missing user_id", "success": False, "equipment_history": [], "total_submissions": 0})

            # Fetch equipment_access from users table
            response = self.supabase.table("users").select("equipment_access").eq("id", user_id).execute()

            if not response.data:
                return json.dumps({"success": True, "equipment_history": [], "total_submissions": 0})

            equipment_history = response.data[0].get('equipment_access', [])

            if not isinstance(equipment_history, list):
                equipment_history = []

            # Return in reverse chronological order (newest first)
            equipment_history_sorted = sorted(
                equipment_history,
                key=lambda x: x.get('timestamp', ''),
                reverse=True
            )

            return json.dumps({
                "success": True,
                "equipment_history": equipment_history_sorted,
                "total_submissions": len(equipment_history_sorted)
            })

        except Exception as e:
            print(f"❌ Error fetching equipment history: {e}")
            return json.dumps({"error": str(e), "success": False, "equipment_history": [], "total_submissions": 0})

    def delete_equipment(self, data):
        """
        Deletes a specific equipment submission by ID.
        Also deletes the corresponding media file from storage.
        """
        try:
            user_id = data.get('user_id')
            submission_id = data.get('submission_id')

            if not user_id or not submission_id:
                return json.dumps({"error": "Missing user_id or submission_id", "success": False})

            # Fetch current equipment_access
            response = self.supabase.table("users").select("equipment_access, gym_media_url").eq("id", user_id).execute()

            if not response.data:
                return json.dumps({"error": "User not found", "success": False})

            user_data = response.data[0]
            equipment_history = user_data.get('equipment_access', [])

            if not isinstance(equipment_history, list):
                equipment_history = []

            # Find the submission to delete
            submission_to_delete = None
            updated_history = []

            for submission in equipment_history:
                if submission.get('id') == submission_id:
                    submission_to_delete = submission
                else:
                    updated_history.append(submission)

            if not submission_to_delete:
                return json.dumps({"error": "Submission not found", "success": False})

            # Delete media file from storage
            try:
                gym_media_path = user_data.get('gym_media_url', f"{user_id}/")
                filename = submission_to_delete.get('filename')
                if filename:
                    full_path = f"{gym_media_path}{filename}"
                    self.supabase.storage.from_('gym_media').remove([full_path])
                    print(f"🗑️ Deleted media file: {full_path}")
            except Exception as storage_error:
                print(f"⚠️ Error deleting storage file: {storage_error}")
                # Continue even if storage deletion fails

            # Update equipment_access in database
            self.supabase.table("users").update({
                "equipment_access": updated_history
            }).eq("id", user_id).execute()

            print(f"✅ Deleted equipment submission {submission_id} for user {user_id}")

            return json.dumps({
                "success": True,
                "message": "Equipment deleted successfully",
                "deleted_id": submission_id
            })

        except Exception as e:
            print(f"❌ Error deleting equipment: {e}")
            import traceback
            traceback.print_exc()
            return json.dumps({"error": str(e), "success": False})

    def delete_all_equipment(self, data):
        """
        Deletes all equipment submissions for a user.
        Also deletes all media files from the gym_media bucket.
        """
        try:
            user_id = data.get('user_id')

            if not user_id:
                return json.dumps({"error": "Missing user_id", "success": False})

            # Fetch current equipment_access
            response = self.supabase.table("users").select("equipment_access, gym_media_url").eq("id", user_id).execute()

            if not response.data:
                return json.dumps({"error": "User not found", "success": False})

            user_data = response.data[0]
            equipment_history = user_data.get('equipment_access', [])
            gym_media_path = user_data.get('gym_media_url', f"{user_id}/")

            # Delete all media files from storage
            deleted_count = 0
            if isinstance(equipment_history, list):
                for submission in equipment_history:
                    try:
                        filename = submission.get('filename')
                        if filename:
                            full_path = f"{gym_media_path}{filename}"
                            self.supabase.storage.from_('gym_media').remove([full_path])
                            deleted_count += 1
                    except Exception as storage_error:
                        print(f"⚠️ Error deleting file {filename}: {storage_error}")
                        # Continue deleting other files

            # Clear equipment_access in database
            self.supabase.table("users").update({
                "equipment_access": []
            }).eq("id", user_id).execute()

            print(f"🗑️ Deleted all equipment for user {user_id}: {deleted_count} files")

            return json.dumps({
                "success": True,
                "message": f"All equipment deleted ({deleted_count} items)",
                "deleted_count": deleted_count
            })

        except Exception as e:
            print(f"❌ Error deleting all equipment: {e}")
            import traceback
            traceback.print_exc()
            return json.dumps({"error": str(e), "success": False})

    @observe(as_type="generation")
    def extract_dad_os_rule(self, data):
        """
        Extract Dad OS Rule from audio file.

        Flow:
        1. Receive audio data (base64 encoded)
        2. Convert to m4a format
        3. Upload to Supabase Storage (dad_audio bucket)
        4. Transcribe with Whisper
        5. Extract rule with Gemini
        6. Validate and insert into Dad_OS_Rules table

        Expected input:
        {
            "audio_data": "base64_encoded_audio",
            "audio_format": "mp3" | "wav" | "m4a"  (optional, default: m4a)
        }

        Returns:
        {
            "success": true,
            "transcript": "...",
            "extracted_rule": {...},
            "rule_id": "uuid",
            "audio_url": "https://..."
        }
        OR
        {
            "success": false,
            "error": "...",
            "stage": "transcription" | "extraction" | "validation"
        }
        """
        try:
            # --- STEP 1: Extract Audio Data ---
            audio_b64 = data.get('audio_data')
            audio_format = data.get('audio_format', 'm4a')

            if not audio_b64:
                return json.dumps({
                    "success": False,
                    "error": "Missing audio_data",
                    "stage": "input"
                })

            # Decode base64
            try:
                audio_bytes = base64.b64decode(audio_b64)
                print(f"📥 Received audio: {len(audio_bytes)} bytes, format: {audio_format}")
            except Exception as e:
                return json.dumps({
                    "success": False,
                    "error": f"Invalid base64 audio data: {str(e)}",
                    "stage": "input"
                })

            # --- STEP 2: Convert to M4A (if needed) ---
            if audio_format.lower() != 'm4a':
                print(f"🔄 Converting {audio_format} to m4a...")
                try:
                    audio_bytes = convert_to_m4a(audio_bytes, audio_format)
                except Exception as e:
                    return json.dumps({
                        "success": False,
                        "error": str(e),
                        "stage": "conversion"
                    })

            # --- STEP 3: Upload to Supabase Storage ---
            print("☁️ Uploading to Supabase Storage...")
            try:
                audio_url = upload_to_storage(audio_bytes, self.supabase)
            except Exception as e:
                return json.dumps({
                    "success": False,
                    "error": str(e),
                    "stage": "storage"
                })

            # --- STEP 4: Transcribe with Whisper ---
            print("🎤 Transcribing audio...")
            try:
                transcript = transcribe_audio(audio_bytes)
            except Exception as e:
                return json.dumps({
                    "success": False,
                    "error": str(e),
                    "stage": "transcription",
                    "audio_url": audio_url  # Return URL even if transcription fails
                })

            # --- STEP 5: Extract Rule with Gemini ---
            print("🧠 Extracting rule with Gemini...")
            try:
                extracted_rule = extract_rule_with_gemini(transcript, self.model)
            except Exception as e:
                return json.dumps({
                    "success": False,
                    "error": str(e),
                    "stage": "extraction",
                    "audio_url": audio_url,
                    "transcript": transcript  # Return transcript for debugging
                })

            # --- STEP 6: Validate and Insert ---
            print("✅ Validating and inserting rule...")
            try:
                success, message, rule_id = validate_and_insert_rule(
                    extracted_rule,
                    audio_url,
                    self.supabase
                )

                if not success:
                    return json.dumps({
                        "success": False,
                        "error": message,
                        "stage": "validation",
                        "audio_url": audio_url,
                        "transcript": transcript,
                        "extracted_rule": extracted_rule  # Return for debugging
                    })

                # Success!
                return json.dumps({
                    "success": True,
                    "transcript": transcript,
                    "extracted_rule": extracted_rule,
                    "rule_id": rule_id,
                    "audio_url": audio_url,
                    "message": message
                })

            except Exception as e:
                return json.dumps({
                    "success": False,
                    "error": str(e),
                    "stage": "database",
                    "audio_url": audio_url,
                    "transcript": transcript,
                    "extracted_rule": extracted_rule
                })

        except Exception as e:
            print(f"❌ Unexpected error in extract_dad_os_rule: {e}")
            import traceback
            traceback.print_exc()
            return json.dumps({
                "success": False,
                "error": f"Unexpected error: {str(e)}",
                "stage": "unknown"
            })
