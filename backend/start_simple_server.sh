#!/bin/bash

# Start the Simple API Server for Health Tracker

echo "🚀 Starting Simple API Server for Health Tracker..."
echo "📍 Endpoints: /transcribe and /analyze-image"

# Check if GEMINI_API_KEY is set
if [ -z "$GEMINI_API_KEY" ]; then
    echo "⚠️  Warning: GEMINI_API_KEY is not set"
    echo "Please set it with: export GEMINI_API_KEY='your-api-key'"
fi

# Run the server
python3 simple_api_server.py