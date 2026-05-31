#!/usr/bin/env python3
"""
Simple API Server for Health Tracker
Provides endpoints for transcription and image analysis
"""

import os
import json
import base64
import asyncio
from aiohttp import web
from aiohttp_cors import setup, ResourceOptions
from google import genai


async def transcribe_handler(request):
    """
    Transcribe audio to text using Gemini
    """
    try:
        data = await request.json()
        audio_base64 = data.get('audio')
        mime_type = data.get('mime_type', 'audio/webm')

        if not audio_base64:
            return web.json_response({"error": "No audio provided"}, status=400)

        # Create client using Vertex AI (same as gemini_live_streaming_simple.py)
        client = genai.Client(
            vertexai=True,
            project=os.environ.get("GOOGLE_CLOUD_PROJECT", "gen-lang-client-0009721575"),
            location="us-central1"
        )

        # Create prompt for transcription
        prompt = "Transcribe this audio to text. Only return the transcription, nothing else."

        # Process audio
        audio_bytes = base64.b64decode(audio_base64)

        response = client.models.generate_content(
            model='gemini-2.0-flash-exp',
            contents=[
                prompt,
                {
                    'mime_type': mime_type,
                    'data': audio_bytes
                }
            ]
        )

        transcription = response.text.strip()
        print(f"✅ Transcribed: {transcription}")

        return web.json_response({
            "transcription": transcription,
            "status": "success"
        })

    except Exception as e:
        print(f"❌ Transcription error: {e}")
        import traceback
        traceback.print_exc()
        return web.json_response({
            "error": str(e),
            "status": "error"
        }, status=500)


async def analyze_image_handler(request):
    """
    Analyze image and return description using Gemini
    """
    try:
        data = await request.json()
        image_base64 = data.get('image')
        mime_type = data.get('mime_type', 'image/jpeg')
        custom_prompt = data.get('custom_prompt')

        # Create client using Vertex AI (same as gemini_live_streaming_simple.py)
        client = genai.Client(
            vertexai=True,
            project=os.environ.get("GOOGLE_CLOUD_PROJECT", "gen-lang-client-0009721575"),
            location="us-central1"
        )

        # Check if this is a synthesis request (custom prompt provided)
        if custom_prompt:
            # Direct synthesis without image
            response = client.models.generate_content(
                model='gemini-2.0-flash-exp',
                contents=custom_prompt
            )
        else:
            # Regular image analysis
            if not image_base64:
                return web.json_response({"error": "No image provided"}, status=400)

            # Create context-aware prompt
            prompt = """Analyze this image in the context of a health tracker app.
            If it's food: Describe the food items, portions, and estimate if it's healthy or a cheat meal.
            If it's workout/exercise: Describe the activity, equipment, or setting.
            If it's something else: Provide a brief relevant description.
            Keep the response concise (1-2 sentences)."""

            # Process image
            image_bytes = base64.b64decode(image_base64)

            response = client.models.generate_content(
                model='gemini-2.0-flash-exp',
                contents=[
                    prompt,
                    {
                        'mime_type': mime_type,
                        'data': image_bytes
                    }
                ]
            )

        description = response.text.strip()
        print(f"✅ Analyzed: {description}")

        return web.json_response({
            "description": description,
            "status": "success"
        })

    except Exception as e:
        print(f"❌ Analysis error: {e}")
        import traceback
        traceback.print_exc()
        return web.json_response({
            "error": str(e),
            "status": "error"
        }, status=500)


async def health_check(request):
    """Health check endpoint"""
    return web.Response(text="OK")


def create_app():
    """Create and configure the application"""
    app = web.Application()

    # Add routes
    app.router.add_get('/health', health_check)
    app.router.add_post('/transcribe', transcribe_handler)
    app.router.add_post('/analyze-image', analyze_image_handler)

    # Setup CORS
    cors = setup(app, defaults={
        "*": ResourceOptions(
            allow_credentials=True,
            expose_headers="*",
            allow_headers="*",
            allow_methods="*"
        )
    })

    # Configure CORS on all routes
    for route in list(app.router.routes()):
        cors.add(route)

    return app


if __name__ == '__main__':
    # Set Google Application Credentials if available
    service_key_path = os.path.expanduser('~/gemini-service-key.json')
    if os.path.exists(service_key_path):
        os.environ['GOOGLE_APPLICATION_CREDENTIALS'] = service_key_path
        print(f"✅ Using service account: {service_key_path}")

    # Set project if not already set
    if not os.environ.get("GOOGLE_CLOUD_PROJECT"):
        os.environ["GOOGLE_CLOUD_PROJECT"] = "gen-lang-client-0009721575"

    app = create_app()
    print("🚀 Starting Simple API Server on http://localhost:8080")
    print("📍 Endpoints:")
    print("   POST /transcribe - Transcribe audio to text")
    print("   POST /analyze-image - Analyze images")
    print("   GET /health - Health check")
    print(f"🔧 Using Vertex AI with project: {os.environ.get('GOOGLE_CLOUD_PROJECT')}")
    web.run_app(app, host='0.0.0.0', port=8080)