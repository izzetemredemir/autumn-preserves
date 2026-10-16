#!/usr/bin/env python3
"""Keep tools/asset_log.csv: one row per asset, so every asset can be regenerated.

  add      upsert a row (same asset_id replaces the old row)
  approve  mark a row approved by a human
  show     compact table (optionally one family)

  python log_asset.py add --id goldfish_gray --file tools/style/anchor_goldfish_gray.png \
      --family fish --model openai/gpt-image-2.5/flare/edit \
      --prompt-file tools/style/prompts/goldfish.txt --ref tools/style/raw/keyart_v1.png \
      --cleanup "--size 32x32 --mode value-map" --notes "raw: tools/style/raw/goldfish_v1.png"
  python log_asset.py approve goldfish_gray --by user
  python log_asset.py show --family fish
"""
import argparse
import csv
import datetime
import hashlib
import os

COLUMNS = ["asset_id", "file_path", "family", "model", "prompt_sha1", "seed", "reference_image",
           "date_utc", "cleanup_args", "aseprite_edited", "approved_by", "notes"]


def read_rows(path):
    if not os.path.exists(path):
        return []
    with open(path, encoding="utf-8") as f:
        return list(csv.DictReader(f))


def write_rows(path, rows):
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with open(path, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=COLUMNS, extrasaction="ignore")
        w.writeheader()
        w.writerows(rows)


def now():
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--log", default="tools/asset_log.csv")
    sub = p.add_subparsers(dest="cmd", required=True)
    a = sub.add_parser("add")
    a.add_argument("--id", required=True)
    a.add_argument("--file", required=True)
    a.add_argument("--family", default="")
    a.add_argument("--model", default="")
    a.add_argument("--prompt-file", default="", help="prompt text file (sha1 is stored; keep the file in git)")
    a.add_argument("--seed", default="")
    a.add_argument("--ref", default="", help="reference image path or URL")
    a.add_argument("--cleanup", default="", help="pixel_cleanup.py args used")
    a.add_argument("--aseprite", action="store_true", help="edited by hand/Aseprite after cleanup")
    a.add_argument("--notes", default="")
    ap = sub.add_parser("approve")
    ap.add_argument("asset_id")
    ap.add_argument("--by", required=True)
    s = sub.add_parser("show")
    s.add_argument("--family", default="")
    args = p.parse_args()

    rows = read_rows(args.log)
    if args.cmd == "add":
        sha = ""
        if args.prompt_file:
            with open(args.prompt_file, encoding="utf-8") as f:
                sha = hashlib.sha1(f.read().encode()).hexdigest()
            args.notes = (args.notes + "; " if args.notes else "") + f"prompt: {args.prompt_file}"
        row = {"asset_id": args.id, "file_path": args.file, "family": args.family, "model": args.model,
               "prompt_sha1": sha, "seed": args.seed, "reference_image": args.ref, "date_utc": now(),
               "cleanup_args": args.cleanup, "aseprite_edited": "y" if args.aseprite else "n",
               "approved_by": "", "notes": args.notes}
        rows = [r for r in rows if r["asset_id"] != args.id] + [row]
        write_rows(args.log, rows)
        print(f"logged {args.id}")
    elif args.cmd == "approve":
        hit = [r for r in rows if r["asset_id"] == args.asset_id]
        if not hit:
            raise SystemExit(f"no row with asset_id={args.asset_id}")
        for r in hit:
            r["approved_by"] = f"{args.by} {now()[:10]}"
        write_rows(args.log, rows)
        print(f"approved {args.asset_id}")
    else:
        for r in rows:
            if args.family and r["family"] != args.family:
                continue
            ok = "✓" if r["approved_by"] else "·"
            model = "/".join(r["model"].split("/")[-2:])
            print(f"{ok} {r['asset_id']:<28} {r['family']:<8} {model:<28} {r['file_path']}")


if __name__ == "__main__":
    main()
