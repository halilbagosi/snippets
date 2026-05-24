import json

transcript_path = "/Users/halilbagosi/.gemini/antigravity/brain/a3bebfb0-204b-458c-adc9-d534690f2bbc/.system_generated/logs/transcript.jsonl"
with open(transcript_path, 'r') as f:
    lines = f.readlines()

for line in lines:
    try:
        step = json.loads(line)
        if step.get("type") == "VIEW_FILE":
            content = step.get("content", "")
            if "ContentView.swift" in content:
                print(f"--- STEP {step.get('step_index')} VIEW_FILE ---")
                print(content[:200] + "...\n")
                
                # We can dump the full content to a file to inspect
                with open(f"view_file_{step.get('step_index')}.swift", "w") as out:
                    out.write(content)
    except:
        pass
