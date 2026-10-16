#!/usr/bin/env python3
"""Make generated audio game-ready with ffmpeg: trim, loudness, fades, seamless loop, format.

  audio_post.py IN|URL --out game/assets/audio/sfx/sfx_feed_drop.wav --kind sfx
  audio_post.py IN --out game/assets/audio/music/mus_main_01.ogg --kind music --loop --crossfade 2
  audio_post.py IN --out game/assets/audio/ambient/amb_rain.ogg --kind ambient --loop --max-sec 30

kind presets (override with flags):
  sfx      trim silence, mono 44.1 kHz WAV 16-bit, peak -3 dBFS, 5 ms fade-in / 30 ms fade-out
  music    stereo OGG q5, loudness -16 LUFS (true peak -1.5), no trim
  ui       like sfx but peak -6 dBFS (UI must not cover game sounds)
  ambient  stereo OGG q4, loudness -24 LUFS, usually --loop
--loop builds a seamless loop: the last C seconds are equal-power crossfaded into the first C
seconds, so the file wraps without a click (result is C seconds shorter).
Prints a JSON report (duration, LUFS, true peak) — check it instead of listening to every file.
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.request

PRESETS = {
    "sfx": {"lufs": None, "peak": -3.0, "mono": True, "trim": True, "fade_in": 0.005, "fade_out": 0.03, "fmt": "wav"},
    "music": {"lufs": -16.0, "peak": None, "mono": False, "trim": False, "fade_in": 0.0, "fade_out": 0.0, "fmt": "ogg", "q": 5},
    "ui": {"lufs": None, "peak": -6.0, "mono": True, "trim": True, "fade_in": 0.003, "fade_out": 0.02, "fmt": "wav"},
    "ambient": {"lufs": -24.0, "peak": None, "mono": False, "trim": False, "fade_in": 0.0, "fade_out": 0.0, "fmt": "ogg", "q": 4},
}


def run(cmd):
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit(f"ffmpeg failed: {' '.join(cmd[:6])} ...\n{r.stderr[-1500:]}")
    return r


def duration(path):
    r = run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "default=nw=1:nk=1", path])
    return float(r.stdout.strip())


def measure(path):
    """Integrated loudness + true peak via ebur128."""
    r = subprocess.run(["ffmpeg", "-hide_banner", "-nostats", "-i", path, "-af", "ebur128=peak=true", "-f", "null", "-"],
                       capture_output=True, text=True)
    txt = r.stderr[r.stderr.rfind("Summary:"):]
    i = re.search(r"I:\s+(-?[\d.]+|-inf) LUFS", txt)
    p = re.search(r"Peak:\s+(-?[\d.]+|-inf) dBFS", txt)
    to_f = lambda m: float(m.group(1)) if m and m.group(1) != "-inf" else None
    return to_f(i), to_f(p)


def loudnorm_2pass(path, target):
    """Measure first, then normalize linearly: lands within ~0.3 LU of the target (one-pass loudnorm drifts ±1.5)."""
    r = subprocess.run(["ffmpeg", "-hide_banner", "-nostats", "-i", path, "-af",
                        f"loudnorm=I={target}:TP=-1.5:LRA=11:print_format=json", "-f", "null", "-"],
                       capture_output=True, text=True)
    m = json.loads(r.stderr[r.stderr.rfind("{"):r.stderr.rfind("}") + 1])
    return (f"loudnorm=I={target}:TP=-1.5:LRA=11:measured_I={m['input_i']}:measured_TP={m['input_tp']}:"
            f"measured_LRA={m['input_lra']}:measured_thresh={m['input_thresh']}:offset={m['target_offset']}:linear=true")


def max_volume(path):
    r = subprocess.run(["ffmpeg", "-hide_banner", "-i", path, "-af", "volumedetect", "-f", "null", "-"],
                       capture_output=True, text=True)
    m = re.search(r"max_volume:\s+(-?[\d.]+) dB", r.stderr)
    return float(m.group(1)) if m else 0.0


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("src", help="input file or http(s) URL")
    p.add_argument("--out", required=True)
    p.add_argument("--kind", choices=PRESETS, required=True)
    p.add_argument("--loop", action="store_true")
    p.add_argument("--crossfade", type=float, default=1.5, help="loop crossfade seconds")
    p.add_argument("--max-sec", type=float, default=0, help="cut input to this length first (0 = off)")
    p.add_argument("--lufs", type=float, help="override loudness target")
    p.add_argument("--peak", type=float, help="override peak target dBFS (sfx)")
    p.add_argument("--no-trim", action="store_true")
    p.add_argument("--raw-dir", default="tools/audio/raw", help="where URL downloads are kept")
    a = p.parse_args()
    cfg = dict(PRESETS[a.kind])
    if a.lufs is not None:
        cfg["lufs"], cfg["peak"] = a.lufs, None
    if a.peak is not None:
        cfg["peak"], cfg["lufs"] = a.peak, None
    if a.no_trim:
        cfg["trim"] = False

    src = a.src
    if src.startswith("http"):
        os.makedirs(a.raw_dir, exist_ok=True)
        name = os.path.basename(src.split("?")[0]) or "download"
        dst = os.path.join(a.raw_dir, f"{os.path.splitext(os.path.basename(a.out))[0]}__{name}")
        urllib.request.urlretrieve(src, dst)
        src = dst

    peak_in = max_volume(src)
    if peak_in < -35:
        sys.exit(f"{src}: source is almost silent (max {peak_in:.1f} dB) - regenerate it with a louder, clearer prompt")

    tmp = tempfile.mkdtemp()
    stage = os.path.join(tmp, "a.wav")
    # 1) decode, optional cut, trim, channel layout
    filters = []
    if cfg["trim"]:
        filters.append("silenceremove=start_periods=1:start_threshold=-50dB:start_silence=0.005,"
                       "areverse,silenceremove=start_periods=1:start_threshold=-50dB:start_silence=0.01,areverse")
    cmd = ["ffmpeg", "-y", "-hide_banner", "-loglevel", "error", "-i", src]
    if a.max_sec:
        cmd += ["-t", str(a.max_sec)]
    if filters:
        cmd += ["-af", ",".join(filters)]
    cmd += ["-ar", "44100", "-ac", "1" if cfg["mono"] else "2", "-c:a", "pcm_s16le", stage]
    run(cmd)
    if cfg["trim"] and os.path.getsize(stage) < 4410:      # trimming ate (almost) everything: keep the untrimmed take
        print(f"warning: silence trim left <0.05 s of {src}; using it untrimmed", file=sys.stderr)
        cmd = [c for c in cmd if c not in filters and c != "-af"]
        run(cmd)

    # 2) seamless loop: head = fadein(A[0:C]) + fadeout(A[L-C:L]); loop = head + A[C:L-C]
    if a.loop:
        L = duration(stage)
        C = min(a.crossfade, L / 3)
        looped = os.path.join(tmp, "b.wav")
        fc = (f"[0:a]asplit=3[a][b][c];"
              f"[a]atrim=0:{C},asetpts=PTS-STARTPTS,afade=t=in:d={C}:curve=qsin[h];"
              f"[b]atrim={L - C}:{L},asetpts=PTS-STARTPTS,afade=t=out:d={C}:curve=qsin[t];"
              f"[h][t]amix=inputs=2:normalize=0[hm];"
              f"[c]atrim={C}:{L - C},asetpts=PTS-STARTPTS[r];"
              f"[hm][r]concat=n=2:v=0:a=1[out]")
        run(["ffmpeg", "-y", "-hide_banner", "-loglevel", "error", "-i", stage, "-filter_complex", fc,
             "-map", "[out]", "-c:a", "pcm_s16le", looped])
        stage = looped

    # 3) level + fades + encode
    post = []
    if cfg["lufs"] is not None:
        post.append(loudnorm_2pass(stage, cfg["lufs"]))
    elif cfg["peak"] is not None:
        post.append(f"volume={cfg['peak'] - max_volume(stage):.2f}dB")
    if not a.loop:
        if cfg["fade_in"]:
            post.append(f"afade=t=in:d={cfg['fade_in']}")
        if cfg["fade_out"]:
            d = duration(stage)
            post.append(f"afade=t=out:st={max(0.0, d - cfg['fade_out']):.3f}:d={cfg['fade_out']}")
    os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
    cmd = ["ffmpeg", "-y", "-hide_banner", "-loglevel", "error", "-i", stage]
    if post:
        cmd += ["-af", ",".join(post)]
    if cfg["fmt"] == "wav":
        run(cmd + ["-ar", "44100", "-c:a", "pcm_s16le", a.out])
    else:
        # Godot plays Ogg Vorbis (not Opus). Prefer ffmpeg's libvorbis, else oggenc (brew install vorbis-tools).
        has_libvorbis = "libvorbis" in subprocess.run(["ffmpeg", "-hide_banner", "-encoders"],
                                                      capture_output=True, text=True).stdout
        if has_libvorbis:
            run(cmd + ["-ar", "44100", "-c:a", "libvorbis", "-q:a", str(cfg.get("q", 5)), a.out])
        elif shutil.which("oggenc"):
            leveled = os.path.join(tmp, "c.wav")
            run(cmd + ["-ar", "44100", "-c:a", "pcm_s16le", leveled])
            run(["oggenc", "-Q", "-q", str(cfg.get("q", 5)), "-o", a.out, leveled])
        else:
            sys.exit("no Vorbis encoder: install vorbis-tools (oggenc) or an ffmpeg with libvorbis")

    lufs, peak = measure(a.out)
    print(json.dumps({"out": a.out, "kind": a.kind, "loop": a.loop, "duration_s": round(duration(a.out), 3),
                      "lufs": lufs, "true_peak_dbfs": peak, "source": src,
                      "godot": "enable Loop in import (OGG: loop=true; WAV: loop_mode Forward)" if a.loop else ""}))


if __name__ == "__main__":
    main()
