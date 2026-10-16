#!/bin/zsh
# Generates the synthetic evaluation set from eval/fixtures.json into build/fixtures (not committed).
# Requires macOS `say` voices named in the file and ffmpeg.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/build/fixtures"
mkdir -p "$OUT"
python3 -I - "$ROOT/eval/fixtures.json" "$OUT" <<'PY'
import json, subprocess, sys, tempfile, os
spec, out = json.load(open(sys.argv[1])), sys.argv[2]
for item in spec["items"]:
    target = os.path.join(out, item["id"] + ".wav")
    with tempfile.TemporaryDirectory() as tmp:
        pieces = []
        voices = item.get("voice")
        for i, text in enumerate(item["parts"]):
            voice = voices[i] if isinstance(voices, list) else voices
            aiff = os.path.join(tmp, f"{i}.aiff")
            subprocess.run(["say", "-v", voice, "-o", aiff, text], check=True)
            wav = os.path.join(tmp, f"{i}.wav")
            subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", aiff, "-ar", "16000", "-ac", "1", wav], check=True)
            pieces.append(wav)
            if i < len(item["parts"]) - 1 and item.get("pause"):
                gap = os.path.join(tmp, f"gap{i}.wav")
                subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i", f"anullsrc=r=16000:cl=mono", "-t", str(item["pause"]), gap], check=True)
                pieces.append(gap)
        if not pieces:
            pieces.append(os.path.join(tmp, "silence.wav"))
            subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i", "anullsrc=r=16000:cl=mono", "-t", str(item.get("silence", 2)), pieces[0]], check=True)
        lst = os.path.join(tmp, "list.txt")
        open(lst, "w").write("".join(f"file '{p}'\n" for p in pieces))
        joined = os.path.join(tmp, "joined.wav")
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "concat", "-safe", "0", "-i", lst, "-ar", "16000", "-ac", "1", joined], check=True)
        filters = []
        if item.get("gain_db"):
            filters.append(f"volume={item['gain_db']}dB")
        src = joined
        if item.get("noise_snr_db") or item.get("noise_only_db"):
            level = item.get("noise_only_db", -20 - 0)
            amp = 10 ** (((-20 - item["noise_snr_db"]) if item.get("noise_snr_db") else item["noise_only_db"]) / 20)
            noisy = os.path.join(tmp, "noisy.wav")
            subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", joined, "-f", "lavfi", "-i", f"anoisesrc=color=pink:amplitude={amp:.4f}:sample_rate=16000:seed=7",
                            "-filter_complex", "[0][1]amix=inputs=2:duration=first:normalize=0", "-ar", "16000", "-ac", "1", noisy], check=True)
            src = noisy
        args = ["ffmpeg", "-v", "error", "-y", "-i", src]
        if filters:
            args += ["-af", ",".join(filters)]
        subprocess.run(args + ["-ar", "16000", "-ac", "1", "-c:a", "pcm_s16le", target], check=True)
    print("wrote", target)
PY
