# SandEE — Revised Waypoint Draft

**Status: visual concept only. Nothing here is implemented in gameplay.**

This revision selects the requested set:

- **Python dungeon waypoint:** Stonegate Portal + Python crystal mark
- **Lua dungeon waypoint:** Ancient Rune Gate + Lua crystal mark
- **World waypoint:** Ruined Skyglass Tower only
- **Beacon Tower:** excluded from this selected set

## Language crystal marks

The portal crests now use language-specific crystal emblems rather than the
generic gold diamond:

- **Python mark:** two interlocking blue/gold crystal shards based on the
  language colours in `extension/python.svg` (`#8aadf4` blue, `#eed49f` gold).
- **Lua mark:** a blue crystal orb with a crescent cut and a small satellite
  crystal, based on `extension/lua.svg` (`#1e66f5` / `#89b4fa`).

Both sit in a small stone-and-gold setting at the top centre of their portal. These are proposed crystal treatments of the Python/Lua language marks, not new production assets.

## Animations

All three selected waypoints now have 8-frame, 100 ms/frame loops (10 fps,
1.0 s seamless loops). The static structure bodies stay fixed; the magical
parts animate independently.

### Python Stonegate Portal

- Animated cyan/green veil arcs, pulsing core, drifting motes, blue/gold
  language-mark aura, and side-crystal glints.
- `portal_python_stonegate_loop.png` / `.apng` — transparent animated source
- `portal_python_stonegate_loop.gif` — checkerboard animation preview
- `sprites/portal_python_stonegate_animated_sheet.png` — 8-frame sheet
- `frames/portal_python_stonegate_00.png` … `_07.png`

### Lua Ancient Rune Gate

- Animated violet veil arcs, pulsing core, rotating gold rune points, blue
  language-mark aura, and an orbiting Lua satellite shard.
- `portal_lua_ancient_loop.png` / `.apng` — transparent animated source
- `portal_lua_ancient_loop.gif` — checkerboard animation preview
- `sprites/portal_lua_ancient_animated_sheet.png` — 8-frame sheet
- `frames/portal_lua_ancient_00.png` … `_07.png`

### Ruined Skyglass Tower

- **Native frame size:** 160×224 px, 5×7 world tiles
- **Animated parts:** crystal bob (±2 px), faceted shimmer, four orbiting
  shards, rune-ring pulse, and one-pixel aura motes
- **Static tower body:** unchanged across frames, so the tower can be a single
  static sprite plus a small animated beacon overlay if desired.
- `tower_skyglass_loop.png` / `.apng` — transparent animated source
- `tower_skyglass_loop.gif` — checkerboard animation preview
- `sprites/tower_skyglass_animated_sheet.png` — 8-frame sheet
- `frames/tower_skyglass_00.png` … `_07.png`
- `tower_skyglass_world_loop.gif` — world-scale animated preview

### Combined selected-set loop

- `waypoint_selected_world_loop.gif` — Python portal, Lua portal, and animated
  world tower together at approximately 1.9× game zoom.
- `waypoint_selected_world.png` — first-frame static version.
- `portal_animation_strip.png` — Python/Lua key-frame comparison.
- `tower_animation_strip.png` — all eight tower frames.

## Files

| File | Purpose |
| --- | --- |
| `waypoint_revised_closeups.png` | Python / Lua portal close-ups, tower, animation keyframes, language-mark close-ups |
| `waypoint_revised_world.png` | Selected set at approximately the game's 1.9× zoom |
| `waypoint_selected_world_loop.gif` | All three selected waypoints animating in one world-scale mock |
| `language_crystals.png` | Enlarged Python / Lua crystal-mark comparison |
| `portal_animation_strip.png` | Python/Lua key-frame comparison |
| `tower_animation_strip.png` | All 8 tower frames labelled |
| `portal_python_stonegate_loop.gif` | Python portal animation preview |
| `portal_lua_ancient_loop.gif` | Lua portal animation preview |
| `tower_skyglass_loop.gif` | Tower animation preview |
| `sprites/portal_python_stonegate.png` | Python portal frame 0, 160×128 px |
| `sprites/portal_lua_ancient.png` | Lua portal frame 0, 192×160 px |
| `sprites/tower_skyglass_ruined.png` | Tower frame 0, 160×224 px |
| `sprites/*_animated_sheet.png` | Transparent 8-frame sprite sheets |
| `sprites/*_x4.png` | Nearest-neighbour close-up exports |
| `build_waypoint_revision.py` | Rebuilds this revision from code |

Suggested pivots are bottom-centre for all three structures. The portal
thresholds and tower foundations sit on the bottom tile row.

## Materials referenced

Stone, Granite, Diorite, Sandstone/gold trim, Wood/planks, the existing dungeon
portal cyan/violet/green magic palette, and the language colours from the
project's Python/Lua editor icons and language specifications.

No production sprite, scene, script, save file, or world-generation asset was
changed by this revision. This remains a review-only draft.
