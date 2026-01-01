

import os
import vertexai
from vertexai.generative_models import GenerativeModel, Part
from supabase import create_client, Client
from tools.google_tools import GoogleTools  # <--- NEW: Import the Eyes
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
        # --- Step C: Construct the Prompt (Thought) ---
        prompt = f"""
        You are a smart Nutrition Agent.
        
        1. WHO: User {user_id}
        2. MEMORY (Last 5 Logs): {recent_logs}
        3. WHERE (Location): {location_context}
        4. TIME: {self.get_current_time_str()}
        DECISION LOGIC:
        - If 'Location' is a fast-food place (e.g., McDonald's), WARN them. Suggest a healthier item from THAT menu.
        - If 'Location' is a Gym, congratulate them.
        - If 'Memory' shows no food in 6 hours, suggest a snack.
        Output only JSON: {{ "action": "NOTIFICATION", "message": "..." }} or {{ "action": "NONE" }}
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
