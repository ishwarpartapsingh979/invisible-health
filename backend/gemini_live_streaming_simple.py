#!/usr/bin/env python3
"""
Minimal Gemini Live API - Audio Streaming
Just the basics: receive audio from iOS, send to Gemini, stream response back
"""

import os
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

            # Send initial greeting
            await session.send_realtime_input(text="Hey! How can I help you today?")

            # Start task to stream Gemini responses to iOS
            async def stream_responses():
                async for response in session.receive():
                    if response.data:
                        # Send audio back to iOS
                        await ws.send_bytes(response.data)

            response_task = asyncio.create_task(stream_responses())

            # Listen for audio from iOS
            chunk_count = 0
            async for msg in ws:
                if msg.type == aiohttp.WSMsgType.BINARY:
                    # Forward audio to Gemini (VAD will detect silence automatically)
                    chunk_count += 1

                    # Debug: Check audio data
                    if chunk_count == 1:
                        print(f"🎵 First chunk: {len(msg.data)} bytes, first 20 bytes: {msg.data[:20].hex()}")

                    if chunk_count % 20 == 0:
                        print(f"📥 Forwarded {chunk_count} audio chunks to Gemini")
                        # Check if audio is actually silence
                        import struct
                        samples = struct.unpack('<' + 'h' * (len(msg.data) // 2), msg.data)
                        max_amplitude = max(abs(s) for s in samples) if samples else 0
                        print(f"🔊 Audio level: {max_amplitude}/32768 (PCM16 amplitude)")

                    await session.send_realtime_input(
                        audio=types.Blob(
                            data=msg.data,
                            mime_type="audio/pcm;rate=16000"
                        )
                    )

                    # Test: After 100 chunks (~10 seconds), manually signal end
                    if chunk_count == 100:
                        print(f"⚡ Testing: Sending manual activity_end after 100 chunks")
                        await session.send_realtime_input(activity_end=types.ActivityEnd())

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
