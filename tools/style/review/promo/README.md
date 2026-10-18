# Promo illustrations: candidates (PROMO-ART)

Scenes P1–P7 of `docs/jury/promo-plan.md` §2. Every scene has its own labelled sheet here, and the human picks one candidate per scene.

## Status, 18 Oct 04:50

All seven scenes are picked, and their finals are in `tools/publish/promo/`. Each final is the candidate at exactly 2× with nearest neighbour, stored as an indexed PNG, and passes the palette check:

| Scene | Picked | Final |
|---|---|---|
| P1 | v1 | `P1_city_winter.png` (1920×1080) |
| P2 | v5 (round 3) | `P2_teo_photo.png` |
| P3 | v2 | `P3_letter.png` |
| P4 | v2 | `P4_valley_map.png` |
| P5 | v2 | `P5_people.png` (Nora as drawn here is now her approved reference) |
| P6 | v1 | `P6_pantry_snow.png` |
| P7 | v2 | `P7_poster.png` (1080×1620) |

**P2 was rejected.** The human's note: "ikisi de yaşlı ve tonton olmalı" ("both should be old and chubby"). The photo is the one on the mantel, from their later years, not from their youth. Round 3 (`promo_P2_r3.txt`) draws them both elderly. Tonty matches the game's Granny exactly. Teo has white hair, a white beard, a brimmed felt hat and a wine-red waistcoat. The colours are faded and sepia-tinted, but her red cardigan and green skirt still show. The candidates are **v4** (seed 1017) and **v5** (seed 2026), on `P2_teo_photo.png`, which now shows only round 3. The rejected v1–v3 stay in `tools/style/raw/promo/` and the log.

**The human picked P2 v5** (18 Oct), which was also my recommendation. It fits the mantel caption: Teo smiles gently but doesn't laugh ("He is laughing in every photo but this one"). The gate, the pear tree and the cottage are all in frame, which leaves room for parallax. v4 frames them closer and is more emotional, but Teo laughs in it.

The table below is the first round as it was handed in, with my recommendations at the time.

**How they were made.** Every candidate comes from the key-art generator, `openai/gpt-image-2.5/flare/edit`. The first two references are always the same style anchors: the picked key art (`tools/publish/key_art.png`) and the title painting (`bg_title`). Each scene adds a third reference for its characters or room, listed in the table. The two candidates of a scene share one prompt and differ only in seed, 1017 or 2026. Each raw went through `tools/pipeline/pixel_cleanup.py --size 960x540 --fit cover --resample box --bg none --palette tools/palettes/autumn.hex`, the same flags as the key art. P7 used `--size 540x810`. All 17 cleaned PNGs (15 from the first round plus the two P2 round-3 candidates) pass `pixel_cleanup.py --check` with 0 off-palette pixels and no partial alpha. No image has text in it. Titles, names and the QR code are added later in Remotion or in the deck.

**Files.** The raws are `tools/style/raw/promo/promo_<scene>_v<N>.png`. The cleaned candidates are `..._v<N>_960.png`, or `..._540.png` for P7. The cell labels on the sheets are these file stems. Every generation has its own row in `tools/asset_log.csv` (`promo_<scene>_v<N>`, family `promo`). Each row holds the seed, the reference URLs and the result URL.

**After the pick.** Each final is the picked candidate scaled up exactly 2× with nearest neighbour, the same as the key art. Wide scenes become 1920×1080 and the poster becomes 1080×1620. For an A3 print, scale the poster ×6 to 3240×4860. The finals go in `tools/publish/promo/`. Then mark the pick in the log with `python3 tools/pipeline/log_asset.py approve promo_<scene>_v<N> --by <name>`.

| Scene | Sheet | Prompt | Third reference | Candidates | Pick | Why |
|---|---|---|---|---|---|---|
| P1 Winter in the city | `P1_city_winter.png` | `promo_P1.txt` | Mia and Leo portrait sheet (`portraits_kids`) | v1, v2 | **v2** | The left of the frame is calm snowy sky, so the trailer title has space, and both children's faces and the empty jar read clearly in the one warm window. v1 fills the left with rooftops and a street lamp. |
| P2 Teo and Tonty (rejected, see Status) | `P2_teo_photo.png` now shows round 3; this round is in git history | `promo_P2.txt` (v1, v2), `promo_P2_r2.txt` (v3) | Granny reference sheet | v1, v2, v3 | **v3** | Only v3 makes Tonty clearly young: she has dark hair, while in v1 and v2 her pale sepia bun reads as grey. Teo wears a brimmed felt hat like the one on the parlour peg. v3 is the one regeneration. |
| P3 The letter | `P3_letter.png` | `promo_P3.txt` | Granny reference sheet | v1, v2 | **v1** | Both hands unfold the letter in the middle of the frame, and the snowflake stamp, tea, jam and peeking cat all read at a glance. The letter lines can't be read. |
| P4 Map of the Everfall valley | `P4_valley_map.png` | `promo_P4.txt` | (style references only) | v1, v2 | **v2** | It has more open parchment between the cottage, forest, vineyard, stream, village and mountain road, which leaves room for the deck's loop arrows. v1 is richer but more crowded. |
| P5 The people of Everfall | `P5_people.png` | `promo_P5.txt` | The 8 game portraits at ×6 (`tools/style/raw/promo/ref_portraits_x6.png`) | v1, v2 | **v1** | The nine cards are evenly spaced with Tonty's card the largest, and every face matches its game portrait. The name plaques are empty and ready for the deck. v2 has a stray frame in the bottom-left corner. |
| P6 Full pantry, first snow | `P6_pantry_snow.png` | `promo_P6.txt` | The game's pantry (`bg_pantry_v1.png`) | v1, v2 | **v1** | It is the fuller and more balanced room: glowing shelves, a lantern, snow at the window and the cat asleep on the stool. The upper-left wall is still calm enough for a title. v2 has a bigger empty ceiling but an odd corner. |
| P7 Poster (portrait 2:3) | `P7_poster.png` | `promo_P7.txt` | Granny reference sheet | v1, v2 | **v2** | It is the key art set upright. The top third is calmer, open sky for the logo, and the path at the bottom is calm for the tagline and QR. v1 has busier clouds. |

**For the human to check**

- **P4:** In both maps the snowy city on the far right looks like a fairy-tale town with spires, not the brick apartments of P1. It is small and works as "far away", but if it bothers you, a regeneration could ask for brick blocks.
- **P1 and P5:** Mia's yellow raincoat comes out pale cream or chartreuse after the palette snap, the same as her game portrait.
- **Nora:** Nora is new in P5. She has chestnut hair, a red scarf and a slate-blue coat. If she is approved, she is the reference for any later Nora art.
- **P8:** The jar catalogue is not part of this card. It is a game render in JURY-KIT.
