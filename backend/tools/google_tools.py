import os
import requests
import vertexai
from vertexai.generative_models import Tool, GroundingSource
from langfuse.decorators import observe  # <--- NEW
class GoogleTools:
    """
    The Eyes of the Agent.
    Wraps Google Maps and Google Search.
    """
    def __init__(self):
        self.maps_key = os.environ.get("GOOGLE_MAPS_KEY")
        if not self.maps_key:
            print("Warning: GOOGLE_MAPS_KEY not found. Maps features will fail.")
    @observe(as_type="tool")
    def get_places_nearby(self, lat: float, lng: float, radius: int = 500, type: str = "restaurant"):
        """
        Equivalent to: mcp-google-maps
        Finds places near the user using Google Places API (New).
        """
        url = "https://places.googleapis.com/v1/places:searchNearby"
        headers = {
            "Content-Type": "application/json",
            "X-Goog-Api-Key": self.maps_key,
            "X-Goog-FieldMask": "places.displayName,places.primaryType,places.priceLevel,places.rating,places.userRatingCount"
        }
        payload = {
            "includedTypes": [type],
            "maxResultCount": 5,
            "locationRestriction": {
                "circle": {
                    "center": {"latitude": lat, "longitude": lng},
                    "radius": radius
                }
            }
        }
        try:
            response = requests.post(url, json=payload, headers=headers)
            response.raise_for_status()
            return response.json()
        except Exception as e:
            return {"error": f"Maps API failed: {str(e)}"}
    def get_search_tool(self):
        """
        Equivalent to: mcp-vertex-search (Grounding)
        Returns the Tool configuration to enable Google Search Grounding.
        The Agent passes this to the model, and the model decides when to search.
        """
        tool = Tool.from_google_search_retrieval(
            google_search_retrieval=vertexai.generative_models.GoogleSearchRetrieval()
        )
        return tool

