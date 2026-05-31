#!/usr/bin/env python3
"""
Minimal Gemini Live API - Audio Streaming
Just the basics: receive audio from iOS, send to Gemini, stream response back
"""

import os
import json
import base64
import asyncio
from aiohttp import web
import aiohttp
from aiohttp_cors import setup, ResourceOptions

from google import genai
from google.genai import types
from google.genai.types import LiveConnectConfig, VoiceConfig, SpeechConfig
import google.generativeai as genai_standard


async def websocket_handler(request):
    """
    WebSocket endpoint - minimal implementation
    """
    ws = web.WebSocketResponse()
    await ws.prepare(request)

    try:
        # Wait for start message from iOS
        msg = await ws.receive()
        if msg.type != aiohttp.WSMsgType.TEXT:
            print("❌ Expected text message for initialization")
            return ws

        data = json.loads(msg.data)
        print(f"📱 iOS start message: {data}")

        # Send acknowledgment to iOS
        await ws.send_json({"status": "connected", "message": "Ready for audio"})

        # Initialize Gemini client
        client = genai.Client(
            vertexai=True,
            project=os.environ.get("GOOGLE_CLOUD_PROJECT"),
            location="us-central1"
        )

        # Connect to Gemini Live API with proper configuration
        config = LiveConnectConfig(
            response_modalities=["AUDIO"],
            speech_config=SpeechConfig(
                voice_config=VoiceConfig(
                    prebuilt_voice_config=types.PrebuiltVoiceConfig(
                        voice_name="Kore"  # Deep, warm voice
                    )
                )
            )
        )

        # Use the correct model for Vertex AI
        model = "gemini-live-2.5-flash-native-audio"
        print(f"🔧 Connecting to model: {model}")
        print(f"🔧 Config: {config}")

        try:
            async with client.aio.live.connect(model=model, config=config) as session:

                # Send initial greeting to test connection
                print("🎤 Session ready - sending test greeting")
                try:
                    await session.send(text="Hello! I can hear you. Please speak and then press the Done button when finished.")
                    print("✅ Test greeting sent")
                except Exception as e:
                    print(f"⚠️ send(text) failed: {e}, trying legacy method...")
                    await session.send_realtime_input(text="Hello! I can hear you. Please speak and then press the Done button when finished.")
                    print("✅ Test greeting sent (legacy)")

                # Start task to stream Gemini responses to iOS
                async def stream_responses():
                    print("👂 Started listening for Gemini responses...")
                    try:
                        async for response in session.receive():
                            print(f"📨 Received response from Gemini: {type(response)}")

                            # Check response type and fields
                            if hasattr(response, 'server_content'):
                                if response.server_content:
                                    # Check for audio in server_content
                                    if hasattr(response.server_content, 'model_turn') and response.server_content.model_turn:
                                        for part in response.server_content.model_turn.parts:
                                            if hasattr(part, 'inline_data') and part.inline_data:
                                                audio_bytes = part.inline_data.data
                                                print(f"🎵 Audio from model_turn: {len(audio_bytes)} bytes")
                                                # Send as Base64 JSON to iOS
                                                audio_response = {
                                                    "type": "audio",
                                                    "data": base64.b64encode(audio_bytes).decode('utf-8'),
                                                    "mime_type": "audio/pcm;rate=24000"
                                                }
                                                await ws.send_json(audio_response)

                                    if response.server_content.turn_complete:
                                        print(f"✅ Turn complete signal received")

                            # Legacy format support
                            if hasattr(response, 'data') and response.data:
                                print(f"🎵 Audio data (legacy): {len(response.data)} bytes")
                                # Send as Base64 JSON to iOS
                                audio_response = {
                                    "type": "audio",
                                    "data": base64.b64encode(response.data).decode('utf-8'),
                                    "mime_type": "audio/pcm;rate=24000"
                                }
                                await ws.send_json(audio_response)

                            if hasattr(response, 'text') and response.text:
                                print(f"📝 Text response: {response.text}")
                    except Exception as e:
                        print(f"❌ Error in response streaming: {e}")
                        import traceback
                        traceback.print_exc()

                response_task = asyncio.create_task(stream_responses())

                # Listen for audio and control messages from iOS
                chunk_count = 0
                async for msg in ws:
                    if msg.type == aiohttp.WSMsgType.TEXT:
                        # JSON message from iOS
                        data = json.loads(msg.data)

                        # Handle text input
                        if data.get("type") == "text":
                            text_input = data.get("text", "")
                            print(f"📝 Text input from user: {text_input}")
                            try:
                                await session.send(text=text_input)
                                print("✅ Text sent to Gemini")
                            except Exception as e:
                                print(f"⚠️ send(text) failed: {e}, trying legacy method...")
                                await session.send_realtime_input(text=text_input)
                                print("✅ Text sent (legacy)")

                        # Handle image input
                        elif data.get("type") == "image":
                            image_base64 = data.get("image", "")
                            mime_type = data.get("mime_type", "image/jpeg")
                            print(f"📷 Image received: {mime_type}, {len(image_base64)} chars")
                            try:
                                # Send image with context
                                await session.send(
                                    media=types.Blob(
                                        data=base64.b64decode(image_base64),
                                        mime_type=mime_type
                                    )
                                )
                                print("✅ Image sent to Gemini")
                            except Exception as e:
                                print(f"⚠️ Image send failed: {e}, trying legacy method...")
                                await session.send_realtime_input(
                                    image=types.Blob(
                                        data=base64.b64decode(image_base64),
                                        mime_type=mime_type
                                    )
                                )
                                print("✅ Image sent (legacy)")

                        # Handle context from health tracker
                        elif data.get("type") == "start":
                            context = data.get("context", "")
                            print(f"📊 Health context: {context}")
                            try:
                                await session.send(text=f"Starting health coaching session. {context}")
                                print("✅ Context sent to Gemini")
                            except:
                                await session.send_realtime_input(text=f"Starting health coaching session. {context}")

                        # Check for control messages
                        elif data.get("action") == "end_input":
                            # User pressed "Done Speaking" button
                            print(f"🏁 Manual end signal received from iOS after {chunk_count} chunks")
                            try:
                                # Try sending with send() method
                                await session.send(end_of_turn=True)
                                print(f"✅ end_of_turn sent - Gemini should respond now")
                            except Exception as e:
                                print(f"⚠️ send(end_of_turn) failed: {e}, trying legacy method...")
                                # Fallback to legacy method
                                await session.send_realtime_input(activity_end=types.ActivityEnd())
                                print(f"✅ activity_end sent (legacy) - Gemini should respond now")
                            chunk_count = 0  # Reset for next turn

                        # Check for audio data in JSON format
                        elif "realtime_input" in data:
                            # Extract Base64-encoded audio from JSON
                            realtime_input = data["realtime_input"]
                            if "media_chunks" in realtime_input:
                                for chunk in realtime_input["media_chunks"]:
                                    if "data" in chunk:
                                        # Decode Base64 audio to binary
                                        audio_bytes = base64.b64decode(chunk["data"])
                                        chunk_count += 1

                                        # Debug first chunk and periodic updates
                                        if chunk_count == 1:
                                            print(f"🎵 First audio chunk: {len(audio_bytes)} bytes (from Base64 JSON)")

                                        if chunk_count % 20 == 0:
                                            print(f"📥 Forwarded {chunk_count} audio chunks to Gemini")

                                        # Forward audio to Gemini
                                        try:
                                            # Try the new send() method with media parameter
                                            await session.send(
                                                media=types.Blob(
                                                    data=audio_bytes,
                                                    mime_type="audio/pcm;rate=16000"
                                                )
                                            )
                                        except Exception as e:
                                            # Fallback to legacy method if new method fails
                                            if "send() got an unexpected keyword argument 'media'" in str(e):
                                                await session.send_realtime_input(
                                                    audio=types.Blob(
                                                        data=audio_bytes,
                                                        mime_type="audio/pcm;rate=16000"
                                                    )
                                                )
                                            else:
                                                print(f"❌ Error sending audio: {e}")

                    elif msg.type == aiohttp.WSMsgType.BINARY:
                        # Legacy binary audio data (for backward compatibility)
                        chunk_count += 1
                        print(f"⚠️ Received legacy binary audio - iOS should send Base64 JSON instead")

                        if chunk_count == 1:
                            print(f"🎵 First audio chunk: {len(msg.data)} bytes (legacy binary)")

                        # Forward audio to Gemini (legacy support)
                        try:
                            await session.send(
                                media=types.Blob(
                                    data=msg.data,
                                    mime_type="audio/pcm;rate=16000"
                                )
                            )
                        except:
                            await session.send_realtime_input(
                                audio=types.Blob(
                                    data=msg.data,
                                    mime_type="audio/pcm;rate=16000"
                                )
                            )

                    elif msg.type == aiohttp.WSMsgType.ERROR:
                        break

                print(f"✅ Total audio chunks forwarded: {chunk_count}")

                response_task.cancel()

        except Exception as e:
            print(f"Error: {e}")
            import traceback
            traceback.print_exc()

    except Exception as e:
        print(f"WebSocket handler error: {e}")
        import traceback
        traceback.print_exc()

    return ws


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

        # Initialize Gemini standard API
        genai_standard.configure(api_key=os.environ.get("GEMINI_API_KEY"))

        # Use Gemini 1.5 Flash for transcription
        model = genai_standard.GenerativeModel('gemini-1.5-flash')

        # Create prompt for transcription
        prompt = "Transcribe this audio to text. Only return the transcription, nothing else."

        # Process audio
        response = model.generate_content([
            prompt,
            {
                "mime_type": mime_type,
                "data": audio_base64
            }
        ])

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

        # Initialize Gemini standard API
        genai_standard.configure(api_key=os.environ.get("GEMINI_API_KEY"))

        # Use Gemini 1.5 Flash for analysis
        model = genai_standard.GenerativeModel('gemini-1.5-flash')

        # Check if this is a synthesis request (custom prompt provided)
        if custom_prompt:
            # Direct synthesis without image
            response = model.generate_content(custom_prompt)
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
            response = model.generate_content([
                prompt,
                {
                    "mime_type": mime_type,
                    "data": image_base64
                }
            ])

        description = response.text.strip()
        print(f"✅ Image analyzed: {description}")

        return web.json_response({
            "description": description,
            "status": "success"
        })

    except Exception as e:
        print(f"❌ Image analysis error: {e}")
        import traceback
        traceback.print_exc()
        return web.json_response({
            "error": str(e),
            "status": "error"
        }, status=500)


async def health_check(request):
    return web.Response(text="OK")


def create_app():
    app = web.Application()

    # Add routes
    app.router.add_get('/health', health_check)
    app.router.add_get('/ws', websocket_handler)
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
    app = create_app()
    port = int(os.environ.get('PORT', 8080))
    print(f"🚀 Starting server on 0.0.0.0:{port}")
    print(f"📍 Health check endpoint: http://0.0.0.0:{port}/health")
    print(f"🔌 WebSocket endpoint: ws://0.0.0.0:{port}/ws")
    web.run_app(app, host='0.0.0.0', port=port)
