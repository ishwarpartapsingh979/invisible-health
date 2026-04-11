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
            return ws

        data = json.loads(msg.data)
        print(f"📱 iOS message: {data}")

        # Initialize Gemini client
        client = genai.Client(
            vertexai=True,
            project=os.environ.get("GOOGLE_CLOUD_PROJECT"),
            location="us-central1"
        )

        # Connect to Gemini Live API
        config = {
            "response_modalities": ["AUDIO"]
        }

        async with client.aio.live.connect(model="gemini-live-2.5-flash-native-audio", config=config) as session:

            # Don't send initial greeting - let user speak first
            print("🎤 Session ready - user can speak first")

            # Start task to stream Gemini responses to iOS
            async def stream_responses():
                print("👂 Started listening for Gemini responses...")
                try:
                    async for response in session.receive():
                        print(f"📨 Received response from Gemini: {type(response)}")

                        # Check all possible response fields
                        if hasattr(response, 'server_content'):
                            if response.server_content and response.server_content.turn_complete:
                                print(f"✅ Turn complete signal received")

                        if response.data:
                            print(f"🎵 Audio data: {len(response.data)} bytes")
                            # Send audio back to iOS
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
                        await session.send_realtime_input(activity_end=types.ActivityEnd())
                        print(f"✅ activity_end sent - Gemini should respond now")
                        chunk_count = 0  # Reset for next turn

                elif msg.type == aiohttp.WSMsgType.BINARY:
                    # Audio data from iOS
                    chunk_count += 1

                    # Debug first chunk and periodic updates
                    if chunk_count == 1:
                        print(f"🎵 First audio chunk: {len(msg.data)} bytes")

                    if chunk_count % 20 == 0:
                        print(f"📥 Forwarded {chunk_count} audio chunks to Gemini")

                    # Forward audio to Gemini
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
