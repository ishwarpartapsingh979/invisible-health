#!/bin/bash

# Start the Gemini Live Streaming Server for Health Coach

echo "🚀 Starting Gemini Live Streaming Server..."
echo "📍 Make sure you're in the backend directory"

# Set the Google Cloud Project
export GOOGLE_CLOUD_PROJECT=gen-lang-client-0009721575

# Set the service account credentials
export GOOGLE_APPLICATION_CREDENTIALS="$HOME/gemini-service-key.json"

echo "✅ Using service account credentials"

# Activate virtual environment and run server
source venv/bin/activate
python gemini_live_streaming_simple.py