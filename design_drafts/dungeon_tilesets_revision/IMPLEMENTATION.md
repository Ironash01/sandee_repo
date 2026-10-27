# Dungeon tileset implementation notes

The approved Lua/Python dungeon art direction is now applied to dungeon
interiors. This file records the production integration; the design review
package remains in `README.md` and `previews/`.

## Production assets

New, theme-specific assets live under:

- `SandEEAlpha/sprites/dungeon/lua/`
- `SandEEAlpha/sprites/dungeon/python/`

Each theme contains:

| File | Use |
| --- | --- |
| `walls.png` | 11 x 32 px wall cells: 9 face-set variants + 2 alternates |
| `floors.png` | 5 x 32 px floor variants |
| `pillar_32x96.png` | free-standing room support |
| `pilaster_32x64.png` | wall support / arch flank |
| `door_frame_96x96.png` | focal arch at room openings |
| `blind_arch_96x64.png` | sealed wall niche |
| `masonry_panel_64x32.png` | bonus-room wall panel |
| `sconce_sheet.png` | 8 frames x 16x32, 10 fps |
| `medallion_sheet.png` | 8 frames x 64x64, 10 fps |

The old shared dungeon ItemData resources remain untouched as a compatibility
fallback. No existing production sprite was overwritten.

## Runtime integration

`DungeonWorld` now:

- Resolves the theme from the dungeon language.
  - `lua` -> Lua Ancient Rune Sanctum.
  - `python` -> Python Stonegate Foundry.
  - Shared/boss/unknown-language dungeons currently fall back to the Python
    theme.
- Builds/reuses a static themed TileSet cache:
  - wall cells receive the same full-tile collision polygon as before;
  - five floor variants are selected deterministically from cell coordinates;
  - buried wall cells occasionally use the two approved alternate variants.
- Uses a theme-specific ambient `CanvasModulate`:
  - Lua is lifted violet (`0.84, 0.78, 0.96`).
  - Python is lifted cool blue (`0.76, 0.88, 0.91`).
  - Existing WorldEnvironment glow remains in use.

## Interior architecture

For each valid room, `DungeonWorld` places a restrained set of props:

- a door frame on a real top-wall opening, or a blind arch on a solid top wall;
- two animated sconces on solid top-wall cells, flanking the focal arch;
- two pilasters in wider rooms;
- two pillar props in larger rooms (at least 8 x 7 tiles);
- a masonry panel instead of an arch in bonus rooms;
- one animated floor medallion where the room centre is free.

Placement avoids altars, player/boss spawns, the exit marker, flares, traps,
quiz guard cells, quiz traps, rare chests, and safe-zone gap cells.

Pillar bases are solid `StaticBody2D` supports. Their grid cells are also added
to an internal blocked-cell set so the existing Hitman grid navigation routes
around them. Other architecture is visual-only and does not alter collision or
pathfinding.

## Animation

Animated:

- **Sconces** - eight-frame crystal flicker at 10 fps, plus a live
  `PointLight2D` whose energy gently pulses.
- **Floor medallions** - eight-frame rune/spark pulse at 10 fps, plus a low
  energy local glow.

Static, because they are architectural masonry rather than active magic:

- walls and floors;
- pillars and pilasters;
- door frames and blind arches;
- masonry panels.

No animation is stored in save data. Dungeon visuals regenerate from the theme
and seed on each visit.

## Verification

- QA suite: **565/565 passed** (latest full run, including the later Lua-track, Python-runner, inventory/chest, PNC/build-mode, layered fullscreen-map, title-panorama, and waypoint recall/tower interaction work).
- New tests verify:
  - 11 wall cells and 5 floor variants load per theme;
  - sconce and medallion sheets produce eight frames;
  - both the first Lua and first Python dungeon use their correct theme;
  - animated sconces/medallions and local lights spawn;
  - pillar bases are registered as blocked navigation cells;
  - existing dungeon placement, enemies, hazards, tutorial, and rare-chest
    checks still pass.
- In-game render checks:
  - `implementation_previews/lua_first_dungeon_in_game.png`
  - `implementation_previews/python_first_dungeon_in_game.png`
  - `implementation_previews/lua_extra_dungeon_in_game.png`
  - `implementation_previews/python_regular_dungeon_in_game.png`
  - `implementation_previews/lua_animated_props.gif`
  - `implementation_previews/python_animated_props.gif`
  - `implementation_previews/in_game_theme_overview.png`

## Known limitations

- Door frames are aligned to top-wall openings only; side/bottom openings keep
  their existing geometry without a door-frame overlay.
- The floor edge/corner transition drafts are not used in this pass. They were
  designed for raised platforms and are better introduced with a dedicated
  platform/dais pass.
- Architecture beyond the pillar bases is non-colliding decoration.
- Boss/shared dungeons currently inherit the Python material theme.
- No APK was exported; Android rendering and safe-area validation remain
  outstanding.
- No game version, save format, mission data, or dungeon generation rule was
  changed.

## Regenerating the applied assets

The production tiles and animations are reproducible from the approved draft:

```text
python design_drafts/dungeon_tilesets_revision/apply_runtime_assets.py
python design_drafts/dungeon_tilesets_revision/build_implementation_previews.py
```

`build_dungeon_tilesets.py` remains the design/source-art generator.
`apply_runtime_assets.py` packs the approved cells into production atlases and
generates the sconce/medallion animation sheets. No existing production asset is
overwritten.

No commit or push was made.
