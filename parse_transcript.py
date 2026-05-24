import json
transcript_path = "/Users/halilbagosi/.gemini/antigravity/brain/a3bebfb0-204b-458c-adc9-d534690f2bbc/.system_generated/logs/transcript.jsonl"
with open(transcript_path, 'r') as f:
    for line in f:
        try:
            step = json.loads(line)
            if "tool_calls" in step:
                for tc in step["tool_calls"]:
                    if "ContentView.swift" in str(tc):
                        print(f"STEP {step.get('step_index')} {tc.get('name')}")
                        args = tc.get("args", {})
                        if "ReplacementChunks" in args:
                            print(str(args["ReplacementChunks"])[:200])
        except: pass
