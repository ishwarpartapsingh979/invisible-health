import functions_framework
import os

# This decorator tells Google: "This function is reachable via HTTP"
@functions_framework.http
def run_agent(request):
    """
    The Entry Point. 
    Handles GET (Cron/Query) and POST (Multimodal Chat).
    """
    try:
        # Lazy import to prevent container crash if dependencies are missing
        from agent_engine import NutritionAgent
        
        # 1. Initialize the Brain
        agent = NutritionAgent()
    except ImportError as e:
        import json
        import traceback
        return json.dumps({"error": f"ImportError: {str(e)}", "trace": traceback.format_exc()}), 500, {'Content-Type': 'application/json'}
    except Exception as e:
        import json
        import traceback
        return json.dumps({"error": f"Error initializing Agent: {str(e)}", "trace": traceback.format_exc()}), 500, {'Content-Type': 'application/json'}

    # --- HANDLE POST (Multimodal Chat) ---
    if request.method == 'POST':
        try:
            # Expect JSON body: { "user_id": "...", "text": "...", "image_data": "...", "audio_data": "..." }
            data = request.get_json(silent=True)
            if not data:
                return "Missing JSON Body", 400
            
            # --- HANDLE UPDATE LOG ---
            if data.get('action') == 'update_log':
                 success, msg = agent.update_log(data)
                 if success: return msg, 200
                 else: return msg, 500
            
            # --- PHASE 3.1: ANALYZE WORKOUT ---
            if data.get('action') == 'analyze_workout':
                # Pass full JSON body
                response_json = agent.analyze_workout(data)
                return response_json, 200, {'Content-Type': 'application/json'}
            
            # --- PHASE 3.3: NIGHTLY REPORT ---
            if data.get('action') == 'nightly_report':
                 response_json = agent.generate_nightly_report(data)
                 return response_json, 200, {'Content-Type': 'application/json'}
                 
            # --- PHASE 3.4: CHAT WITH CONTEXT ---
            if data.get('action') == 'chat':
                response_json = agent.chat_with_context(data)
                return response_json, 200, {'Content-Type': 'application/json'}
            
            # --- PHASE 6.3: COACH CHAT ---
            if data.get('action') == 'chat_with_coach':
                 response_json = agent.chat_with_coach(data)
                 return response_json, 200, {'Content-Type': 'application/json'}

            # --- GLOBAL COACH CHAT ---
            if data.get('action') == 'chat_with_coach_global':
                 response_json = agent.chat_with_coach_global(data)
                 return response_json, 200, {'Content-Type': 'application/json'}

            # --- PREVIEW COACH CHAT ---
            if data.get('action') == 'chat_with_coach_preview':
                 response_json = agent.chat_with_coach_preview(data)
                 return response_json, 200, {'Content-Type': 'application/json'}

            # --- RECOMMENDATION COACH CHAT ---
            if data.get('action') == 'chat_with_coach_recommendation':
                 response_json = agent.chat_with_coach_recommendation(data)
                 return response_json, 200, {'Content-Type': 'application/json'}

            # --- RECOMMENDATION TAB ---
            if data.get('action') == 'workout_recommendation':
                response_json = agent.get_workout_recommendation(data)
                return response_json, 200, {'Content-Type': 'application/json'}

            # --- TOMORROW PREVIEW ---
            if data.get('action') == 'tomorrow_preview':
                response_json = agent.get_tomorrow_preview(data)
                return response_json, 200, {'Content-Type': 'application/json'}

            # --- MCP INTEGRATION: GROCERY & FOOD ORDERING ---
            if data.get('action') == 'search_groceries':
                response_json = agent.search_groceries_mcp(data)
                return response_json, 200, {'Content-Type': 'application/json'}

            if data.get('action') == 'compare_prices':
                response_json = agent.compare_prices_mcp(data)
                return response_json, 200, {'Content-Type': 'application/json'}

            if data.get('action') == 'suggest_protein_sources':
                response_json = agent.suggest_protein_sources_mcp(data)
                return response_json, 200, {'Content-Type': 'application/json'}

            if data.get('action') == 'smart_order':
                response_json = agent.smart_order_from_prompt_mcp(data)
                return response_json, 200, {'Content-Type': 'application/json'}

            if data.get('action') == 'search_restaurants':
                response_json = agent.search_restaurants_mcp(data)
                return response_json, 200, {'Content-Type': 'application/json'}

            if data.get('action') == 'get_menu':
                response_json = agent.get_menu_mcp(data)
                return response_json, 200, {'Content-Type': 'application/json'}

            # --- EQUIPMENT ANALYSIS ---
            if data.get('action') == 'analyze_equipment':
                response_json = agent.analyze_equipment(data)
                return response_json, 200, {'Content-Type': 'application/json'}

            user_id = data.get('user_id')
            text = data.get('text')
            
            # Extract Image OR Audio
            media_data = data.get('image_data') or data.get('audio_data')
            mime_type = data.get('mime_type', 'image/jpeg') # Client should send correct mime type
            
            # Extract Location (Phase 2.1)
            lat = data.get('lat')
            lng = data.get('lng')
            if lat: lat = float(lat)
            if lng: lng = float(lng)
            
            if not user_id:
                return "Missing user_id", 400

            # Process Multimodal
            # Logic: If media_data is present, Gemini determines if it's audio or image based on mime_type
            response = agent.process_multimodal_input(user_id, text, media_data, mime_type, lat=lat, lng=lng)
            
            # Return JSON directly
            return response, 200, {'Content-Type': 'application/json'}
            
        except Exception as e:
            return f"Error processing POST: {str(e)}", 500

    # --- HANDLE GET (Cron / Query) ---
    request_args = request.args
    target_user_id = request_args.get('user_id')
    lat = request_args.get('lat')
    lng = request_args.get('lng')
    steps = request_args.get('steps') # Phase F: HealthKit Steps
    
    if not target_user_id:
        return "Please provide ?user_id=... to check a specific user.", 200
        
    try:
        # Convert lat/lng to float if they exist
        if lat: lat = float(lat)
        if lng: lng = float(lng)
        if steps: steps = int(steps)
        
        if request_args.get('action') == 'log_water':
            agent.log_water(target_user_id)
            return "Water Logged", 200
            
        if request_args.get('action') == 'undo_water':
            agent.undo_water(target_user_id)
            return "Water Undo Successful", 200

        # --- Session Routes (Phase B) ---
        if request_args.get('action') == 'wake_up':
            fcm_token = request_args.get('fcm_token')
            # Pass steps to wake_up (Phase F)
            agent.wake_up(target_user_id, fcm_token, steps)
            return "Agent Woken Up", 200

        if request_args.get('action') == 'heartbeat':
            agent.heartbeat(target_user_id)
            return "Heartbeat Received", 200
            
        if request_args.get('action') == 'midnight_check':
            result = agent.midnight_check()
            return f"Midnight Check Complete: {result}", 200
            
        # --- Data Feed (Phase D) ---
        if request_args.get('action') == 'get_logs':
            logs = agent.get_logs(target_user_id)
            # Return JSON (Supabase response.data is a list of dicts)
            return logs, 200, {'Content-Type': 'application/json'}

        # --- SOS (Phase E) ---
        if request_args.get('action') == 'sos':
            # Returns a JSON string directly from the LLM
            user_input = request_args.get('input')
            strategies = agent.get_sos_strategies(target_user_id, user_input=user_input)
            return strategies, 200, {'Content-Type': 'application/json'}

        # --- GET EQUIPMENT HISTORY ---
        if request_args.get('action') == 'get_equipment':
            equipment_history = agent.get_equipment_history({"user_id": target_user_id})
            return equipment_history, 200, {'Content-Type': 'application/json'}

        # Default: Check Status (Silent Guardian)
        decision = agent.check_user_status(target_user_id, lat=lat, lng=lng, steps=steps)
        
        # 4. Return the result (Logs show what happened)
        return f"Agent Checked User {target_user_id}. Decision: {decision}", 200
        
    except Exception as e:
        return f"Error running agent loop: {str(e)}", 500
