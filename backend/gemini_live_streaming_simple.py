#!/usr/bin/env python3
"""
Minimal Gemini Live API - Audio Streaming
Just the basics: receive audio from iOS, send to Gemini, stream response back
"""

import os
import json
import asyncio
from aiohttp import web
import aiohttp

from google import genai
from google.genai import types
from google.genai.types import LiveConnectConfig, PrebuiltVoiceConfig, SpeechConfig


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
                voice_config=PrebuiltVoiceConfig(
                    voice_name="Kore"  # Deep, warm voice
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
                                                await ws.send_bytes(audio_bytes)

                                    if response.server_content.turn_complete:
                                        print(f"✅ Turn complete signal received")

                            # Legacy format support
                            if hasattr(response, 'data') and response.data:
                                print(f"🎵 Audio data (legacy): {len(response.data)} bytes")
                                await ws.send_bytes(response.data)

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
                        # Control message from iOS
                        data = json.loads(msg.data)

                        if data.get("action") == "end_input":
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

                    elif msg.type == aiohttp.WSMsgType.BINARY:
                        # Audio data from iOS
                        chunk_count += 1

                        # Debug first chunk and periodic updates
                        if chunk_count == 1:
                            print(f"🎵 First audio chunk: {len(msg.data)} bytes")

                        if chunk_count % 20 == 0:
                            print(f"📥 Forwarded {chunk_count} audio chunks to Gemini")

                        # Forward audio to Gemini using proper method
                        try:
                            # Try the new send() method with media parameter
                            await session.send(
                                media=types.Blob(
                                    data=msg.data,
                                    mime_type="audio/pcm;rate=16000"
                                )
                            )
                        except Exception as e:
                            # Fallback to legacy method if new method fails
                            if "send() got an unexpected keyword argument 'media'" in str(e):
                                await session.send_realtime_input(
                                    audio=types.Blob(
                                        data=msg.data,
                                        mime_type="audio/pcm;rate=16000"
                                    )
                                )
                            else:
                                print(f"❌ Error sending audio: {e}")

                    elif msg.type == aiohttp.WSMsgType.ERROR:
                        break

                print(f"✅ Total audio chunks forwarded: {chunk_count}")

                response_task.cancel()

        except Exception as e:
            print(f"Error: {e}")
            import traceback
            traceback.print_exc()

    return ws


async def health_check(request):
    return web.Response(text="OK")


def create_app():
    app = web.Application()
    app.router.add_get('/health', health_check)
    app.router.add_get('/ws', websocket_handler)
    return app


if __name__ == '__main__':
    app = create_app()
    port = int(os.environ.get('PORT', 8080))
    print(f"Starting server on port {port}")
    web.run_app(app, host='0.0.0.0', port=port)
