# Promo illustrations: candidates (PROMO-ART)

Scenes P1–P7 of `docs/jury/promo-plan.md` §2. Every scene has its own labelled sheet here, and the human picks one candidate per scene. These are candidates, not finals.

**How they were made.** Every candidate comes from the key-art generator, `openai/gpt-image-2.5/flare/edit`. The first two references are always the same style anchors: the picked key art (`tools/publish/key_art.png`) and the title painting (`bg_title`). Each scene adds a third reference for its characters or room, listed in the table. The two candidates of a scene share one prompt and differ only in seed, 1017 or 2026. Each raw went through `tools/pipeline/pixel_cleanup.py --size 960x540 --fit cover --resample box --bg none --palette tools/palettes/autumn.hex`, the same flags as the key art. P7 used `--size 540x810`. All 15 cleaned PNGs pass `pixel_cleanup.py --check` with 0 off-palette pixels and no partial alpha. No image has text in it. Titles, names and the QR code are added later in Remotion or in the deck.

**Files.** The raws are `tools/style/raw/promo/promo_<scene>_v<N>.png`. The cleaned candidates are `..._v<N>_960.png`, or `..._540.png` for P7. The cell labels on the sheets are these file stems. Every generation has its own row in `tools/asset_log.csv` (`promo_<scene>_v<N>`, family `promo`). Each row holds the seed, the reference URLs and the result URL.

**After the pick.** Each final is the picked candidate scaled up exactly 2× with nearest neighbour, the same as the key art. Wide scenes become 1920×1080 and the poster becomes 1080×1620. For an A3 print, scale the poster ×6 to 3240×4860. The finals go in `tools/publish/promo/`. Then mark the pick in the log with `python3 tools/pipeline/log_asset.py approve promo_<scene>_v<N> --by <name>`.

| Scene | Sheet | Prompt | Third reference | Candidates | Pick | Why |
|---|---|---|---|---|---|---|
| P1 Winter in the city | `P1_city_winter.png` | `promo_P1.txt` | Mia and Leo portrait sheet (`portraits_kids`) | v1, v2 | **v2** | The left of the frame is calm snowy sky, so the trailer title has space, and both children's faces and the empty jar read clearly in the one warm window. v1 fills the left with rooftops and a street lamp. |
| P2 Teo and Tonty, fifty years ago | `P2_teo_photo.png` | `promo_P2.txt` (v1, v2), `promo_P2_r2.txt` (v3) | Granny reference sheet | v1, v2, v3 | **v3** | Only v3 makes Tonty clearly young: she has dark hair, while in v1 and v2 her pale sepia bun reads as grey. Teo wears a brimmed felt hat like the one on the parlour peg. v3 is the one regeneration. |
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
