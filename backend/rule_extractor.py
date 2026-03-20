import os
import time
import uuid
import json
import base64
import tempfile
from openai import OpenAI
from pydantic import BaseModel, ValidationError
from supabase import Client
from pydub import AudioSegment


class DadOsRule(BaseModel):
    """Pydantic model for Dad OS Rules validation"""
    trigger_conditions: dict = {}
    action_vetoes: list = []
    action_forces: list = []
    veteran_rationale: str


def convert_to_m4a(audio_data: bytes, original_format: str) -> bytes:
    """
    Convert any audio format to m4a for consistency

    Args:
        audio_data: Raw audio bytes
        original_format: Original format (mp3, wav, etc.)

    Returns:
        Audio data in m4a format
    """
    try:
        # Write to temporary input file
        with tempfile.NamedTemporaryFile(suffix=f".{original_format}", delete=False) as tmp_input:
            tmp_input.write(audio_data)
            tmp_input_path = tmp_input.name

        # Create temporary output file path
        tmp_output_path = tempfile.mktemp(suffix=".m4a")

        try:
            # Load and convert
            audio = AudioSegment.from_file(tmp_input_path, format=original_format)
            audio.export(tmp_output_path, format="mp4", codec="aac")

            # Read converted file
            with open(tmp_output_path, 'rb') as f:
                converted_data = f.read()

            return converted_data

        finally:
            # Clean up temp files
            if os.path.exists(tmp_input_path):
                os.unlink(tmp_input_path)
            if os.path.exists(tmp_output_path):
                os.unlink(tmp_output_path)

    except Exception as e:
        raise Exception(f"Audio conversion failed: {str(e)}")


def upload_to_storage(audio_data: bytes, supabase: Client) -> str:
    """
    Upload audio to Supabase Storage dad_audio bucket

    Args:
        audio_data: Audio file bytes (m4a format)
        supabase: Supabase client

    Returns:
        Public URL of uploaded file
    """
    try:
        # Generate unique filename
        filename = f"{int(time.time())}_{uuid.uuid4().hex[:8]}.m4a"

        # Upload to Supabase Storage
        response = supabase.storage.from_("dad_audio").upload(
            filename,
            audio_data,
            {"content-type": "audio/mp4"}
        )

        # Get public URL
        public_url = supabase.storage.from_("dad_audio").get_public_url(filename)

        print(f"✅ Audio uploaded to: {public_url}")
        return public_url

    except Exception as e:
        raise Exception(f"Storage upload failed: {str(e)}")


def transcribe_audio(audio_data: bytes) -> str:
    """
    Transcribe audio using OpenAI Whisper API

    Args:
        audio_data: Audio file bytes

    Returns:
        Transcript text
    """
    try:
        # Initialize OpenAI client
        api_key = os.environ.get("OPENAI_API_KEY")
        if not api_key:
            raise ValueError("OPENAI_API_KEY environment variable not set")

        client = OpenAI(api_key=api_key)

        # Write to temp file (Whisper API needs file-like object)
        with tempfile.NamedTemporaryFile(suffix=".m4a", delete=False) as tmp:
            tmp.write(audio_data)
            tmp_path = tmp.name

        try:
            # Call Whisper API
            with open(tmp_path, "rb") as audio_file:
                transcript = client.audio.transcriptions.create(
                    model="whisper-1",
                    file=audio_file,
                    language="en"  # Change to None for auto-detect or "hi" for Hindi
                )

            print(f"✅ Transcription complete: {len(transcript.text)} characters")
            return transcript.text

        finally:
            # Clean up temp file
            os.unlink(tmp_path)

    except Exception as e:
        raise Exception(f"Transcription failed: {str(e)}")


def extract_rule_with_gemini(transcript: str, model) -> dict:
    """
    Extract Dad OS Rule from transcript using Gemini

    Args:
        transcript: Audio transcript text
        model: Gemini GenerativeModel instance

    Returns:
        Extracted rule as dict
    """
    try:
        system_prompt = """You are an expert Data Engineer extracting logic for an athletic routing engine.
I will provide a transcript of a voice note summarizing a veteran coach's advice.

Your job is to extract the conditional logic from the transcript and output it strictly as a JSON object matching the schema below. Do not include any markdown formatting, explanations, or conversational text. Output ONLY valid JSON.

SCHEMA RULES:
1. "trigger_conditions": Extract the physical, environmental, or psychological state of the user that triggers this rule. (e.g., {"bmi": ">30", "injury": "knee"}).
2. "action_vetoes": A list of exercise types or intensities the coach strictly FORBIDS under these conditions.
3. "action_forces": A list of exercise types or substitutions the coach DEMANDS under these conditions.
4. "veteran_rationale": A concise, 1-2 sentence explanation of WHY the coach made this rule, capturing his veteran intuition.

{
  "trigger_conditions": {},
  "action_vetoes": [],
  "action_forces": [],
  "veteran_rationale": ""
}"""

        prompt = f"{system_prompt}\n\nTRANSCRIPT:\n{transcript}\n\nExtract the rule as JSON:"

        # Call Gemini
        response = model.generate_content(prompt)

        # Parse JSON from response
        extracted_json = json.loads(response.text)

        print(f"✅ Rule extracted: {json.dumps(extracted_json, indent=2)}")
        return extracted_json

    except json.JSONDecodeError as e:
        raise Exception(f"Gemini returned invalid JSON: {response.text}")
    except Exception as e:
        raise Exception(f"Rule extraction failed: {str(e)}")


def validate_and_insert_rule(json_data: dict, audio_url: str, supabase: Client) -> tuple:
    """
    Validate JSON schema and insert into Dad_OS_Rules table

    Args:
        json_data: Extracted rule data
        audio_url: Public URL of source audio
        supabase: Supabase client

    Returns:
        Tuple of (success: bool, message: str, rule_id: str or None)
    """
    try:
        # Validate with Pydantic
        validated = DadOsRule(**json_data)

        # Insert into database
        result = supabase.table("dad_os_rules").insert({
            "trigger_conditions": validated.trigger_conditions,
            "action_vetoes": validated.action_vetoes,
            "action_forces": validated.action_forces,
            "veteran_rationale": validated.veteran_rationale,
            "source_audio_url": audio_url,
            "global_failure_count": 0,
            "hitl_status": "Active"
        }).execute()

        rule_id = result.data[0]['id']
        print(f"✅ Rule inserted with ID: {rule_id}")

        return (True, f"Rule inserted successfully", rule_id)

    except ValidationError as e:
        error_details = json.loads(e.json())
        return (False, f"Validation Error: {error_details}", None)
    except Exception as e:
        return (False, f"Database Error: {str(e)}", None)
