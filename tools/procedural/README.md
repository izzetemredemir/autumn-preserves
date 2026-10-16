# tools/procedural

Deterministic (fixed-seed) generators for PNG art. Run from the repo root; needs numpy + Pillow.

## Forest ground tiles (ART-01)

```
python3 tools/procedural/tiles.py
```

Writes `game/assets/sprites/tiles/forest_tiles.png` (16x16 cells, 4 variants per row, rows = WildGen
ids 0 grass, 1 leaves, 2 dirt, 3 water, 4 path, 5 stone) and `forest_tiles.json` (id -> atlas cells).
Palette: `tools/palettes/autumn.hex`. Ordered (Bayer 4x4) dither only; tiles wrap seamlessly.

## Vineyard and creek art (BIOMES, P1)

```
python3 tools/procedural/biome_art.py
```

Writes `vineyard_tiles.png/json` and `creek_tiles.png/json` (rows = WildGen ids 0-6, 6 = creek bank; 4 variants;
reuses the helpers of `tiles.py`), the vines (`decor_vine`, `tree_grape_ripe|bare`, drawn here), the elder
(`tree_elderberry_ripe|bare`, from the approved pear tree), the rose bush (`bush_rosehip_ripe|bare`, the approved
blackberry bush recoloured), the wild bee hive (`src/bee_hive.src`) and the six P1 icons (`src/icons_p1.src`, same
format as `tools/style/src/icons/icons.src`, so they can be appended there for the icon atlas). No paid generations.
