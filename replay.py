import json

transcript_path = "/Users/halilbagosi/.gemini/antigravity/brain/a3bebfb0-204b-458c-adc9-d534690f2bbc/.system_generated/logs/transcript.jsonl"
file_to_watch = "/Users/halilbagosi/snippets/Sources/Snippets/Views/ContentView.swift"

def unquote(s):
    if isinstance(s, str):
        try:
            return json.loads(s)
        except:
            return s
    return s

with open(transcript_path, 'r') as f:
    lines = f.readlines()

for line in lines:
    try:
        step = json.loads(line)
        if "tool_calls" in step:
            for tc in step["tool_calls"]:
                name = tc.get("name")
                args = tc.get("args", {})
                
                parsed_args = {}
                for k, v in args.items():
                    parsed_args[k] = unquote(v)
                    
                target_file = parsed_args.get("TargetFile")
                if target_file and "ContentView.swift" in target_file:
                    print(f"Found tool call {name} for {target_file} at step {step.get('step_index')}")
                    
    except Exception as e:
        print(e)
