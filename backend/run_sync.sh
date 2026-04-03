#!/bin/bash
# Exercise Sync Runner
# Usage: Export your Supabase credentials, then run this script

# Check if credentials are set
if [ -z "$SUPABASE_URL" ] || [ -z "$SUPABASE_SERVICE_KEY" ]; then
    echo "❌ Error: Supabase credentials not set"
    echo ""
    echo "Set them with:"
    echo "export SUPABASE_URL='your-supabase-url'"
    echo "export SUPABASE_SERVICE_KEY='your-service-key'"
    echo ""
    echo "Then run: ./run_sync.sh"
    exit 1
fi

# Activate venv and run sync
source venv/bin/activate
python3 sync_exercises.py
