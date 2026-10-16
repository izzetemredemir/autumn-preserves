#!/usr/bin/env python3
"""Render every *.txt in this folder to game/assets/sprites/ui/<name>.png. Run from the repo root:
python3 tools/style/src/ui/build.py   (icon_* get the 1 px ink outline from the tool; ui_* sources draw their own)"""
import pathlib, subprocess, sys

SRC = pathlib.Path(__file__).parent
OUT = pathlib.Path("game/assets/sprites/ui")
for t in sorted(SRC.glob("*.txt")):
    extra = ["--outline"] if t.stem.startswith("icon_") else []
    subprocess.check_call([sys.executable, "tools/pipeline/ascii_sprite.py", "render", str(t), "--out", str(OUT / f"{t.stem}.png"), *extra],
                          stdout=subprocess.DEVNULL)
print("ui built")
