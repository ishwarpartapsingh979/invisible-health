import functions_framework
import os
# This decorator tells Google: "This function is reachable via HTTP"
@functions_framework.http
def run_agent(request):
    """
    The Entry Point. 
    Cloud Scheduler hits this URL every 30 minutes.
    """
    try:
        # Lazy import to prevent container crash if dependencies are missing
        from agent_engine import NutritionAgent
        
        # 1. Initialize the Brain
        agent = NutritionAgent()
    except ImportError as e:
        return f"CRITICAL: Dependency Error. check requirements.txt. Details: {str(e)}", 500
    except Exception as e:
        return f"Error initializing Agent: {str(e)}", 500
    # 2. Get All Users (In a real app, we might paginate 1000s of users)
    # For now, we just fetch a test user ID if provided in the URL `?user_id=123`
    # or default to a dummy flow for safety.
    request_args = request.args
    target_user_id = request_args.get('user_id')
    lat = request_args.get('lat')
    lng = request_args.get('lng')
    if not target_user_id:
        return "Please provide ?user_id=... to check a specific user.", 200
    # 3. Run the "Mind Cycle" for that user
    try:
        # Convert lat/lng to float if they exist
        if lat: lat = float(lat)
        if lng: lng = float(lng)
        
        if request_args.get('action') == 'log_water':
            agent.log_water(target_user_id)
            return "Water Logged", 200
        if request_args.get('action') == 'undo_water':
            agent.undo_water(target_user_id)
            return "Water Undo Successful", 200
        # --- Session Routes (Phase B) ---
        if request_args.get('action') == 'wake_up':
            fcm_token = request_args.get('fcm_token')
            agent.wake_up(target_user_id, fcm_token)
            return "Agent Woken Up", 200
        if request_args.get('action') == 'heartbeat':
            agent.heartbeat(target_user_id)
            return "Heartbeat Received", 200
            
        if request_args.get('action') == 'midnight_check':
            result = agent.midnight_check()
            return f"Midnight Check Complete: {result}", 200
        decision = agent.check_user_status(target_user_id, lat=lat, lng=lng)
        
        # 4. Return the result (Logs show what happened)
        return f"Agent Checked User {target_user_id}. Decision: {decision}", 200

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
        return f"CRITICAL: Dependency Error. check requirements.txt. Details: {str(e)}", 500
    except Exception as e:
        return f"Error initializing Agent: {str(e)}", 500

    # --- HANDLE POST (Multimodal Chat) ---
    if request.method == 'POST':
        try:
            # Expect JSON body
            data = request.get_json(silent=True)
            if not data:
                return "Missing JSON Body", 400
            
            user_id = data.get('user_id')
            text = data.get('text')
            
            # Extract Image OR Audio
            media_data = data.get('image_data') or data.get('audio_data')
            mime_type = data.get('mime_type', 'image/jpeg')
            
            if not user_id:
                return "Missing user_id", 400

            # Process Multimodal
            response = agent.process_multimodal_input(user_id, text, media_data, mime_type)
            
            # Return JSON directly
            return response, 200, {'Content-Type': 'application/json'}
            
        except Exception as e:
            return f"Error processing POST: {str(e)}", 500

    # --- HANDLE GET (Cron / Query) ---
    request_args = request.args
    target_user_id = request_args.get('user_id')
    lat = request_args.get('lat')
    lng = request_args.get('lng')
    
    if not target_user_id:
        return "Please provide ?user_id=... to check a specific user.", 200
        
    try:
        # Convert lat/lng to float if they exist
        if lat: lat = float(lat)
        if lng: lng = float(lng)
        
        if request_args.get('action') == 'log_water':
            agent.log_water(target_user_id)
            return "Water Logged", 200
            
        if request_args.get('action') == 'undo_water':
            agent.undo_water(target_user_id)
            return "Water Undo Successful", 200

        # --- Session Routes ---
        if request_args.get('action') == 'wake_up':
            fcm_token = request_args.get('fcm_token')
            agent.wake_up(target_user_id, fcm_token)
            return "Agent Woken Up", 200

        if request_args.get('action') == 'heartbeat':
            agent.heartbeat(target_user_id)
            return "Heartbeat Received", 200
            
        if request_args.get('action') == 'midnight_check':
            result = agent.midnight_check()
            return f"Midnight Check Complete: {result}", 200
            
        # --- Data Feed ---
        if request_args.get('action') == 'get_logs':
            logs = agent.get_logs(target_user_id)
            return logs, 200, {'Content-Type': 'application/json'}

        # --- SOS ---
        if request_args.get('action') == 'sos':
            strategies = agent.get_sos_strategies(target_user_id)
            return strategies, 200, {'Content-Type': 'application/json'}

        # --- Core Decision Loop ---
        decision = agent.check_user_status(target_user_id, lat=lat, lng=lng)
        return f"Agent Checked User {target_user_id}. Decision: {decision}", 200
        
    except Exception as e: # <--- THIS ENSURES THE GET LOGIC IS CLOSED
        return f"Error running agent loop: {str(e)}", 500
