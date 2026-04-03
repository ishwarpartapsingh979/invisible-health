#!/usr/bin/env python3
"""
Sync ExerciseDB Data from Open Source Repository
=================================================
Downloads 800+ exercises from yuhonas/free-exercise-db GitHub repo
and loads them into Supabase exercises table.

Source: https://github.com/yuhonas/free-exercise-db
License: Public Domain

Usage:
    python3 sync_exercises.py

Requirements:
    - Supabase credentials in environment (SUPABASE_URL, SUPABASE_SERVICE_KEY)
    - Internet connection
"""

import os
import json
import requests
from supabase import create_client, Client
from typing import Dict, List, Any

# GitHub raw content URL for exercises.json
EXERCISES_JSON_URL = "https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/dist/exercises.json"

def fetch_exercises_from_github() -> List[Dict[str, Any]]:
    """
    Download exercises.json from GitHub repository

    Returns:
        List of exercise dictionaries
    """
    print("📥 Downloading exercises from GitHub...")
    print(f"   URL: {EXERCISES_JSON_URL}")

    try:
        response = requests.get(EXERCISES_JSON_URL, timeout=30)
        response.raise_for_status()

        exercises = response.json()
        print(f"✅ Downloaded {len(exercises)} exercises")
        return exercises

    except requests.exceptions.RequestException as e:
        print(f"❌ Failed to download exercises: {e}")
        raise
    except json.JSONDecodeError as e:
        print(f"❌ Failed to parse JSON: {e}")
        raise

def transform_exercise(exercise: Dict[str, Any]) -> Dict[str, Any]:
    """
    Transform GitHub exercise format to our Supabase schema

    GitHub format:
    {
        "id": "3_4_Sit-Up",
        "name": "3/4 Sit-Up",
        "force": "pull",
        "level": "beginner",
        "mechanic": "compound",
        "equipment": "body only",
        "primaryMuscles": ["abdominals"],
        "secondaryMuscles": [""],
        "instructions": ["Lie down...", "..."],
        "category": "strength",
        "images": ["3_4_Sit-Up/0.jpg", "3_4_Sit-Up/1.jpg"]
    }

    Our schema:
    {
        "id": "3_4_Sit-Up",
        "name": "3/4 Sit-Up",
        "force": "pull",
        "level": "beginner",
        "mechanic": "compound",
        "equipment": "body only",
        "primary_muscles": ["abdominals"],
        "secondary_muscles": [],
        "instructions": ["Lie down...", "..."],
        "category": "strength",
        "images": ["https://raw.githubusercontent.com/.../0.jpg", "..."]
    }
    """

    # Filter out empty strings from muscle arrays
    primary_muscles = [m for m in exercise.get('primaryMuscles', []) if m and m.strip()]
    secondary_muscles = [m for m in exercise.get('secondaryMuscles', []) if m and m.strip()]

    # Convert relative image paths to full GitHub URLs
    images = []
    for img_path in exercise.get('images', []):
        if img_path:
            full_url = f"https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/{img_path}"
            images.append(full_url)

    return {
        'id': exercise.get('id'),
        'name': exercise.get('name'),
        'force': exercise.get('force'),
        'level': exercise.get('level'),
        'mechanic': exercise.get('mechanic'),
        'equipment': exercise.get('equipment'),
        'primary_muscles': primary_muscles,
        'secondary_muscles': secondary_muscles,
        'instructions': exercise.get('instructions', []),
        'category': exercise.get('category'),
        'images': images
    }

def insert_exercises_to_supabase(exercises: List[Dict[str, Any]], supabase: Client):
    """
    Insert exercises into Supabase in batches

    Args:
        exercises: List of exercise dictionaries
        supabase: Supabase client instance
    """
    print(f"\n📤 Inserting {len(exercises)} exercises into Supabase...")

    BATCH_SIZE = 100
    total = len(exercises)
    success_count = 0
    error_count = 0

    for i in range(0, total, BATCH_SIZE):
        batch = exercises[i:i + BATCH_SIZE]
        batch_num = (i // BATCH_SIZE) + 1
        total_batches = (total + BATCH_SIZE - 1) // BATCH_SIZE

        print(f"   Batch {batch_num}/{total_batches} ({len(batch)} exercises)...", end=" ")

        try:
            # Upsert (insert or update if exists)
            result = supabase.table('exercises').upsert(batch).execute()
            success_count += len(batch)
            print("✅")

        except Exception as e:
            print(f"❌ Error: {e}")
            error_count += len(batch)

    print(f"\n📊 Results:")
    print(f"   ✅ Success: {success_count} exercises")
    print(f"   ❌ Errors: {error_count} exercises")

    return success_count, error_count

def verify_data(supabase: Client):
    """
    Verify exercises were inserted correctly
    """
    print("\n🔍 Verifying data...")

    # Total count
    result = supabase.table('exercises').select('id', count='exact').execute()
    total_count = result.count
    print(f"   Total exercises: {total_count}")

    # Count by equipment
    equipment_types = supabase.table('exercises').select('equipment').execute()
    equipment_counts = {}
    for row in equipment_types.data:
        eq = row.get('equipment', 'unknown')
        equipment_counts[eq] = equipment_counts.get(eq, 0) + 1

    print(f"\n   By equipment:")
    for eq, count in sorted(equipment_counts.items(), key=lambda x: x[1], reverse=True)[:10]:
        print(f"      {eq}: {count}")

    # Sample exercises
    sample = supabase.table('exercises').select('id, name, equipment, primary_muscles').limit(5).execute()
    print(f"\n   Sample exercises:")
    for ex in sample.data:
        print(f"      - {ex['name']} ({ex['equipment']}) → {ex['primary_muscles']}")

def main():
    """
    Main execution flow
    """
    print("=" * 70)
    print("EXERCISEDB SYNC - Open Source Edition")
    print("=" * 70)

    # 1. Check environment
    url = os.environ.get("SUPABASE_URL")
    key = os.environ.get("SUPABASE_SERVICE_KEY")

    if not url or not key:
        print("❌ Error: Supabase credentials not found in environment")
        print("   Set SUPABASE_URL and SUPABASE_SERVICE_KEY")
        return

    print(f"✅ Supabase URL: {url[:30]}...")

    # 2. Initialize Supabase client
    try:
        supabase = create_client(url, key)
        print("✅ Supabase client initialized")
    except Exception as e:
        print(f"❌ Failed to initialize Supabase: {e}")
        return

    # 3. Download exercises from GitHub
    try:
        raw_exercises = fetch_exercises_from_github()
    except Exception as e:
        print(f"❌ Failed to fetch exercises: {e}")
        return

    # 4. Transform to our schema
    print("\n🔄 Transforming exercises to Supabase schema...")
    exercises = [transform_exercise(ex) for ex in raw_exercises]
    print(f"✅ Transformed {len(exercises)} exercises")

    # 5. Insert into Supabase
    success_count, error_count = insert_exercises_to_supabase(exercises, supabase)

    # 6. Verify
    if success_count > 0:
        verify_data(supabase)

    # 7. Summary
    print("\n" + "=" * 70)
    if error_count == 0:
        print("✅ SYNC COMPLETE - All exercises loaded successfully!")
    else:
        print(f"⚠️  SYNC COMPLETE - {error_count} exercises had errors")
    print("=" * 70)

if __name__ == "__main__":
    main()
