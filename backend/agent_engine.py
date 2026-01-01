#
//  agent_engine.py
//  Invisible_Health
//
//  Created by Ishwar Partap Singh on 01/01/26.
//

import os
import vertexai
from vertexai.generative_models import GenerativeModel, Part
from supabase import create_client, Client
class NutritionAgent:
    """
    The Brain of our Application.
    This class manages:
    1. Connection to Supabase (Memory)
    2. Connection to Gemini (Intelligence)
    3. The Decision Loop (Thinking)
    """
    def __init__(self):
        # --- 1. SETUP MEMORY (Supabase) ---
        # We read the URL and Key from the Environment Variables.
        # These are injected by Google Cloud (or your .env file locally).
        url: str = os.environ.get("SUPABASE_URL")
        key: str = os.environ.get("SUPABASE_SERVICE_KEY")
        
        if not url or not key:
            raise ValueError("Missing Supabase Secrets! Did you set SUPABASE_URL and SUPABASE_SERVICE_KEY?")
        # Connect to the Database
        self.supabase: Client = create_client(url, key)
        # --- 2. SETUP BRAIN (Gemini via Vertex AI) ---
        # We initialize the connection to Google's AI Platform.
        # 'project' and 'location' usually default to your GCP project setu
        # but explicit setting is safer if needed.
        vertexai.init()
        # We load the specific model "gemini-1.5-pro-preview-0409" (or latest stable).
        # We pick 1.5 Pro because it is smarter for "Reasoning".
        self.model = GenerativeModel("gemini-1.5-pro")
    def check_user_status(self, user_id: str):
        """
        The Core Loop.
        1. Fetches user context (Logs).
        2. Asks Gemini "What should I do?".
        3. Returns the action.
        """
        # --- Step A: Get Context (Memory) ---
        # Fetch the last 5 food logs for this user.
        response = self.supabase.table("logs") \
            .select("*") \
            .eq("user_id", user_id) \
            .order("created_at", desc=True) \
            .limit(5) \
            .execute()
        
        recent_logs = response.data
        # --- Step B: Construct the Prompt (Thought) ---
        # We tell Gemini who it is and give it data.
        prompt = f"""
        You are a smart Nutrition Agent. 
        Here are the last 5 logs for User {user_id}:
        {recent_logs}
        Current Time: {self.get_current_time_str()}
        DECISION:
        1. If the user hasn't eaten in 6 hours, suggest a snack.
        2. If the user ate junk, suggest a healthy dinner.
        3. Otherwise, do nothing.
        Output only JSON: {{ "action": "NOTIFICATION", "message": "..." }} or {{ "action": "NONE" }}
        """
        # --- Step C: Ask the Brain (Inference) ---
        # We send the text to Gemini and wait for the response.
        chat_response = self.model.generate_content(prompt)
        
        # Return the AI's text (which should be JSON)
        return chat_response.text
    def get_current_time_str(self):
        # Helper to get formatted time (e.g., "Monday, 10:00 AM")
        from datetime import datetime
        return datetime.now().strftime("%A, %I:%M %p")
