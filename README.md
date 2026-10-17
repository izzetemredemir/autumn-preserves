<p align="center">
  <img src="shots/banner.png" alt="Autumn Preserves: a cottage in an autumn valley" width="960">
</p>

<p align="center">
  <b>A cozy pixel-art game about a grandma who puts an endless autumn in jars.</b><br>
  Every forest, every ingredient and every jar is procedurally generated from one seed.
</p>

<p align="center">
  <a href="https://github.com/izzetemredemir/autumn-preserves/releases"><img src="https://img.shields.io/badge/download-macOS%20%7C%20Windows%20%7C%20Web-c94d2e?style=flat-square" alt="Download"></a>
  <img src="https://img.shields.io/badge/Godot-4.7-478cbf?style=flat-square&logo=godotengine&logoColor=white" alt="Godot 4.7">
  <img src="https://img.shields.io/badge/KODT%C3%9C%207-game%20jam-a22512?style=flat-square" alt="KODTÜ 7 game jam">
  <img src="https://img.shields.io/badge/palette-Vintage%20Autumn%2C%2031%20colours-b66813?style=flat-square" alt="Vintage Autumn palette">
  <img src="https://img.shields.io/badge/language-English%20%7C%20T%C3%BCrk%C3%A7e-9b8039?style=flat-square" alt="English and Turkish">
  <img src="https://img.shields.io/badge/code-MIT-53612e?style=flat-square" alt="Code: MIT">
</p>

<p align="center">
  <img src="shots/trailer.gif" alt="Trailer: a forest grows from a seed, Granny shakes a tree, cooks a jam and sells it at the market" width="960">
</p>

Outside the valley of **Everfall** it is winter. Inside, autumn never ends. **Granny Tonty** forages in a forest that did not exist yesterday, cooks what she finds into jams, juices, pickles and pies, arranges the jars on her pantry shelves and shares them with her neighbours, the weekly market and her grandchildren in the city.

Made by **İzzet Emre Demir** for the **KODTÜ 7** game jam (16–18 October 2026).

## Try it in ten minutes

Open the game and press **Harvest Festival** on the title screen. Mia and Leo are visiting, the market is open and everything is unlocked: six small jobs show every system in about ten minutes, and your own save is never touched. The festival ends with a card that tells you which seed your world grew from.

## Highlights

- 🌲 **A new forest every morning.** Value noise, a random-walk stream, Poisson-disk trees, A* paths and weighted pickups, checked by a flood fill so every tree and mushroom can be reached. The same seed always grows the same forest.
- 🫙 **Every jar is generated.** Name, label, jar art, five-axis taste, harmony stars and value come from the recipe, the ingredient variety and the add-in. *Cinnamon Ember Crabapple Jam* is sweet and sour, scores five stars and is worth 233 coins; nobody wrote that by hand.
- 🍳 **Short kitchen mini-games.** Stir the pot, pack the jar, press the juice, knead the dough: about twenty seconds each.
- 🧺 **A pantry puzzle.** The right shelf keeps food fresh, kinds belong together and a pretty shelf earns a third star.
- 🏡 **A living village.** Five neighbours with orders and gifts, a weekly market with five vendors and a crowd of villagers assembled from hand-drawn parts and recoloured from the seed, and letters from the grandchildren with their crayon drawings.
- 🍂 **No death, no penalties, no clock.** A day ends when Granny goes to bed. Stay long enough and the valley has one quiet surprise.
- 🇹🇷 **English or Turkish.** Turkish jar names follow vowel harmony: *Tarçınlı*, *Cevizli*, *Elma Reçeli*.

## Screenshots

| | |
|---|---|
| ![The title screen](shots/title.png) | ![Mia and Leo visit the garden](shots/garden.png) |
| ![Today's forest grows from its seed](shots/grow.png) | ![Shaking a rare tree in the forest](shots/wild.png) |
| ![A new jam: name, taste and value](shots/jam.png) | ![The pantry shelves](shots/pantry.png) |
| ![The weekly market](shots/market.png) | ![A letter from Mia](shots/letters.png) |

## Jam constraints

| Constraint | In the game |
|---|---|
| Pixelated art style | Everything is pixel art at 480×270, scaled by whole numbers only |
| Autumn colour palette | One 31-colour palette, [Vintage Autumn](https://lospec.com/palette-list/vintage-autumn) by Goopy25; every sprite is checked against it automatically |
| Procedural generation | Daily forests in three biomes, ingredient varieties per save, preserves (name, jar art, taste, value, Turkish grammar), orders, weather, critters, market villagers and their routes, children's drawings. The seed is always on screen |

## Controls

| Action | Mouse / touch | Keyboard |
|---|---|---|
| Walk | Click or tap the ground | W A S D or arrow keys |
| Use, pick, talk, shake a tree | Click or tap it | E or Enter |
| Recipe book | | B |
| Rotate a pie or bread on the shelf | Right click | R |
| Stir, press, knead | Circle the pot, click or tap | Space (skim with E) |
| Menu: settings, back to title, quit | The gear in the top bar | Esc |
| Sound on / off | | M |

Everything is playable with the mouse alone.

## Run it

**Builds** for macOS, Windows and the web are on the [Releases](https://github.com/izzetemredemir/autumn-preserves/releases) page. The macOS build is unsigned: right-click the app and choose Open the first time. The game saves locally and needs no network.

<details>
<summary><b>From source</b></summary>

1. Install [Godot 4.7](https://godotengine.org/).
2. Open `game/project.godot` and press Play, or run `godot --path game`.
3. Development builds start muted: press **M**, or run `godot --path game -- --sound`. Exported builds play sound.

</details>

<details>
<summary><b>Behind the scenes: the Forest Lab</b></summary>

Press **L** on the title screen to open the Forest Lab. Type any number or word as a seed, pick a biome and press **G** to watch the forest being built step by step: noise, stream, Poisson-disk trees (with their rejection circles), A* paths, pickups and the flood-fill check. **C** compares two seeds side by side.

</details>

## Credits and license

- **Design, code, art direction:** İzzet Emre Demir.
- **Fonts:** m5x7 and m6x11 by Daniel Linssen. **Palette:** Vintage Autumn by Goopy25. Some art and audio were generated with AI image and music models, then reduced to the palette and edited by hand; see [CREDITS.md](CREDITS.md).
- **Code** (GDScript, shaders, Python tools): MIT, see [LICENSE](LICENSE).
- **Art and audio:** © 2026 İzzet Emre Demir, all rights reserved. They are not covered by the MIT license.
