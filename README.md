<p align="center">
  <img src="website/assets/img/logo.svg" width="96" alt="SandEE logo">
</p>

<h1 align="center">SandEE</h1>

<p align="center">
  <strong>Learn Lua &amp; Python by playing.</strong><br>
  An educational, multi-platform 2D open-world survival crafting game for ICT and STEM students.
</p>

<p align="center">
  <img alt="Godot 4.6" src="https://img.shields.io/badge/Godot-4.6-478CBF?logo=godotengine&amp;logoColor=white">
  <img alt="Platforms: Windows and Android" src="https://img.shields.io/badge/Platforms-Windows%20%7C%20Android-8CE69A">
  <img alt="Status: Alpha" src="https://img.shields.io/badge/Status-Alpha-FFCC66">
  <img alt="Mode: Single-player" src="https://img.shields.io/badge/Mode-Single--player-63C8F0">
</p>

<p align="center">
  <img src="website/assets/img/screenshots/dungeon-lua-01.jpg" width="860"
       alt="SandEE player exploring the Lua Ancient Rune Sanctum">
  <br>
  <sub>Inside the Lua Ancient Rune Sanctum, one of SandEE's themed challenge dungeons.</sub>
</p>

## What is SandEE?

**SandEE** is a capstone thesis project from the Bachelor of Science in Computer Science
program at **STI College San Jose Del Monte**. It is an educational 2D open-world survival
crafting game designed for the Grade 11 and 12 ICT and STEM students of
**Yverdon de Pestalozzi School Inc.**

Players explore a procedurally generated world, gather resources, craft tools and machines,
build shelter, and descend into themed dungeons. What makes SandEE different is that the
game's automation is driven by **real code**. Players write Lua and Python in an in-game
editor to command robots, automate furnaces and crafting stations, and solve dungeon
challenges. Their programs affect the world immediately, including the errors.

SandEE is a **supplementary learning tool**, not a replacement for classroom instruction.
It is meant to make programming practice interactive, contextual, and easier to approach
for beginners.

### Why it exists

A survey of **104 ICT and STEM students** at Yverdon de Pestalozzi School Inc. found that
most were only averagely familiar with Lua, but were highly receptive to learning it through
a game:

| Survey result | Finding |
|---|---|
| **78.9%** | agreed that a game-based approach would improve their understanding of programming |
| **73%** | were motivated to explore Lua through an interactive approach |
| **80.8%** | found Python's syntax and structure easy to understand |
| **104** | Grade 11-12 ICT and STEM respondents |

The project turns that interest into a playable learning environment where syntax,
control flow, functions, and automation are practiced through gameplay.

## How it teaches

| Step | In-game implementation |
|---|---|
| **Introduce** | Mission briefs and Knowledge Altar entries explain concepts and syntax progressively. |
| **Practice** | Themed Lua and Python dungeons give players coding tasks and quiz checkpoints. |
| **Apply** | LUA robots (Live Unit Applications) and Algorithmica stations let players automate real game systems. |
| **Feedback** | Code is parsed and executed in-game; syntax and runtime errors appear in the editor. |

Mission difficulty ramps from **syntax and introductions** on easy missions, to
**functions, loops, and conditions** on medium missions, and **open problem-solving** on
hard missions.

## Feature highlights

- **Open-world survival sandbox** - explore plains, deserts, and snowy biomes; mine, smelt,
  craft, build, farm, fish, and survive day/night cycles.
- **Two programming tracks** - learn Lua through the Automatica/LUA robot line and Python
  through Algorithmica automation.
- **Lua robot stations (LUA)** - place a station, write Lua, and watch your robot mine,
  chop trees, build, deposit items, or enter combat mode. Robots show live status labels
  and can be renamed.
- **Python automation** - program furnaces, crafting stations, and production machines to
  smelt, craft, and process items automatically.
- **Real code execution** - a Rust GDExtension handles Lua and the Python transpilation
  pipeline, so player code produces real output and real errors inside the game.
- **Themed challenge dungeons** - explore the **Lua Ancient Rune Sanctum** and the
  **Python Stonegate Foundry**, solve Knowledge and Quiz Altar challenges, and earn up to
  three stars per dungeon.
- **Caves, dungeons, and minibosses** - large caves, pixie caves, hazards, enemies, and a
  two-room Hitman miniboss encounter.
- **Progression and collection** - mission tracker, blue/yellow stars, encyclopedia
  entries, bestiary, waypoints, and a minimap.
- **Cross-platform accounts** - optional username/password accounts, cloud saves, star
  totals, and leaderboards through Supabase. The game can also be played offline.
- **PC and mobile controls** - keyboard and mouse with point-and-click support on Windows,
  or virtual joystick and contextual touch controls on Android.

## Screenshots

| Lua Ancient Rune Sanctum | Python Stonegate Foundry |
|:---:|:---:|
| ![Lua dungeon gameplay](website/assets/img/screenshots/dungeon-lua-02.jpg) | ![Python dungeon gameplay](website/assets/img/screenshots/dungeon-python-01.jpg) |
| *Branching halls and rune architecture.* | *Stone arches and Python-themed interiors.* |

All screenshots are captured from the actual game.

## Tech stack

| Layer | Technology |
|---|---|
| Game engine | **Godot 4.6** with GDScript |
| Rendering | GLES3 / mobile-compatible renderer; responsive canvas scaling |
| Language runtime | **Rust GDExtension** using `mlua` for Lua and `ruff_python_parser` + GDScript transpilation for Python |
| Game data | Godot `.tres` resources for items, mobs, missions, recipes, structures, and dungeon entries |
| Saves | Local JSON save files plus optional Supabase cloud saves |
| Online backend | **Supabase** Postgres, Auth, Storage, and Edge Functions (`supabase/`) |
| Art | Aseprite and Krita pixel-art assets, tilesets, and animations |
| Website | Static HTML/CSS/JavaScript promo and download page (`website/`) |
| QA | Headless GDScript regression suite (`SandEEAlpha/tests/`) |

### How code execution works

- **Lua** scripts run through the embedded Rust language runtime.
- **Python** source is parsed with `ruff_python_parser` and transpiled to GDScript at
  runtime before execution.
- Both paths report parse/runtime errors back to the in-game editor so debugging is part
  of the learning loop.

## Quick start

### Play the alpha

The current Windows and Android builds are distributed through the static site in
[`website/`](website/). The site includes download buttons, installation notes, and system
requirements.

### Run from source

1. Install **[Godot 4.6](https://godotengine.org/)** (standard build, not .NET).
2. Clone the repository:

   ```powershell
   git clone https://github.com/Ironash01/sandee_repo.git
   cd sandee_repo
   ```

3. Open **`SandEEAlpha/project.godot`** in Godot.
4. Press **F5** to run the project.

The prebuilt Lua/Python extension binaries are included under
`SandEEAlpha/ext_bin/`, so a fresh editor run does not require Python, Lua, or Rust to be
installed. If Godot reports that `LuaState` or `PythonTranspiler` is not declared, the
extension binaries are missing or were built for the wrong platform.

### Rebuild the language extension

The extension lives in `SandEEAlpha/extension/` and is built with Rust. Install a Rust
toolchain with the `x86_64-pc-windows-gnu` target before building:

```powershell
cd SandEEAlpha/extension
cargo build --release --target x86_64-pc-windows-gnu
```

For Windows, copy `target/x86_64-pc-windows-gnu/release/interpreter.dll` into
`SandEEAlpha/ext_bin/release/`, keeping the MinGW runtime DLLs beside it. For Android, use
`build_android.sh` with the configured Android NDK, then place the resulting library in the
matching `SandEEAlpha/ext_bin/` folder. See `SandEEAlpha/extension.gdextension` for the
exact expected paths and runtime DLLs.

### Run the QA suite

```powershell
tools\run_qa.ps1
# or point it at your Godot console binary:
tools\run_qa.ps1 -Godot "C:\path\to\Godot_v4.6-stable_win64_console.exe"
```

The suite is offline and covers world generation, saves, dungeons, missions, automation,
cloud-sync conflict rules, mobile UI safety, and the Lua/Python execution paths. Look for
`QA_RESULT: N/N passed, 0 failed` in the output.

## Controls

| Action | Windows | Android |
|---|---|---|
| Move | `WASD` / arrow keys | Virtual joystick |
| Look / aim / point-and-click | Mouse | Tap |
| Interact / mine / place / attack | Left click | Contextual action buttons |
| Build mode | `Ctrl` | `BUILD` button |
| Sprint | `Shift` | `SPRINT` button |
| Inventory | `E` | Inventory button |
| Hotbar | `1`-`9` | Tap hotbar slots |
| Pause / back | `Esc` | Pause / back button |
| Toggle control guide | `F1` | On-screen controls |

Code editors open when interacting with Lua stations, Python-capable stations, and altar
challenges.

## System requirements

| Requirement | Minimum |
|---|---|
| Operating system | Windows 10 / 11 (64-bit) or Android 8.0+ |
| Processor | Dual-core 2.0 GHz or better |
| Memory | 4 GB RAM |
| Graphics | OpenGL 3.3 / Vulkan / DirectX 12 compatible |
| Storage | 300 MB available space |
| Input | Keyboard and mouse (PC) or touch (Android) |

## Project structure

```text
sandee_repo/
├─ SandEEAlpha/              Godot 4.6 game project
│  ├─ scenes/                Player, mobs, objects, UI, and world scenes
│  ├─ scripts/               GDScript gameplay, UI, world, save, and network code
│  ├─ resources/             Items, mobs, recipes, missions, entries, structures
│  ├─ sprites/               Pixel art, tilesets, characters, and effects
│  ├─ extension/             Rust GDExtension for Lua and Python execution
│  ├─ ext_bin/               Prebuilt extension libraries for each platform
│  └─ tests/                 Headless QA regression suite
├─ supabase/                 Database migrations, RLS, and auth edge function
├─ website/                  Static promo/download site and screenshots
├─ docu_thesis/              Thesis manuscript, forms, and QA documents
├─ docu_gamedocumentation/   Game design and language documentation
├─ design_drafts/            Art exploration, tileset revisions, and sprite concepts
└─ tools/                    Utility scripts, including the QA runner
```

## Cloud saves and accounts

Online features are optional. When enabled, SandEE uses Supabase for:

- username/password accounts,
- private cloud-save storage (up to five worlds per account),
- cross-platform world identity and revision checks,
- mission and dungeon star claims,
- public leaderboards.

The backend is documented in [`supabase/README.md`](supabase/README.md). Never place a
service-role key, database password, or JWT signing secret in the Godot project or in a
commit. The client ships with the publishable key only.

## Thesis and team

**SandEE: An Educational Multi-Platform 2D Open World Survival Crafting Game for Lua and
Python for ICT and STEM Students of Yverdon de Pestalozzi School Inc.**

Bachelor of Science in Computer Science  
Information and Communications Technology Program  
**STI College San Jose Del Monte**

| Name | Role |
|---|---|
| Glenn Marco B. Accad | Developer |
| Adrian V. Gallano | Developer |
| Jefferson G. Mamauag | Developer |
| Jose Mari Christian V. Tayag | Developer |
| Norvin Shaq F. Lintag | Thesis Adviser |

The developers would like to thank the faculty of STI College San Jose Del Monte, the
students and staff of Yverdon de Pestalozzi School Inc. who participated in the survey and
playtesting, and the open-source projects that made the game possible.

## Documentation

- [Thesis manuscript](docu_thesis/main_thesis.pdf)
- [Game documentation](docu_gamedocumentation/)
- [QA regression suite](SandEEAlpha/tests/README.md)
- [Cloud backend](supabase/README.md)
- [Promo and download site](website/)
- [Design drafts and sprite exploration](design_drafts/)

## Feedback

This is an active alpha project. Bug reports, gameplay feedback, and classroom-use
suggestions are welcome through GitHub Issues.

## Academic use

This repository is an academic capstone project. The game, source code, and original assets
are provided for educational review and demonstration. No commercial license is granted.
Please contact the developers before reusing the game's original code or art assets.

Third-party tools and libraries retain their own licenses, including Godot Engine, Rust,
`mlua`, Ruff, and Supabase.
