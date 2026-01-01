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
    if not target_user_id:
        return "Please provide ?user_id=... to check a specific user.", 200
    # 3. Run the "Mind Cycle" for that user
    try:
        decision = agent.check_user_status(target_user_id)
        
        # 4. Return the result (Logs show what happened)
        return f"Agent Checked User {target_user_id}. Decision: {decision}", 200
        
    except Exception as e:
        return f"Error running agent loop: {str(e)}", 500
