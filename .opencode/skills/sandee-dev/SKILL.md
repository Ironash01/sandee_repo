---
name: sandee-dev
description: Use when working on the SandEE Godot 4 game code in this repo — world generation, cave entrances, overworld structures, TileMapLayers, y-sorting/z_index, the player, sprites, or any code under SandEEAlpha/.
---

# SandEE development

**Godot 4.6** GDScript game (user's installed version — code against Godot 4.6
API, not older 4.x). All game code lives under `SandEEAlpha/` — scripts in
`SandEEAlpha/scripts/`, scenes in `SandEEAlpha/scenes/`, sprites in
`SandEEAlpha/sprites/`, structure resources in `SandEEAlpha/resources/structures/`.

## Core conventions

- `TILE_SIZE = 32` everywhere. `GeneratedStructure.TILE_PX` is the structure-grid
  pixel size (also 32).
- World rendering is layered in `world.gd`:
  - `ground_layer` (TileMapLayer) has `z_index = -300` so all world sprites sort above it.
  - `water_layer` cells checked via `water_layer.get_cell_source_id(cell) != -1`.
- Y-sorting: any world-facing node gets a quantized `z_index = int(y / TILE_SIZE)` so
  each row sorts correctly against the player (player walks behind the row above, in
  front of the row below). Player origin is at chest height:
  `z_index = int((global_position.y + 23.0 + 16.0) / 32)` (see `player.gd`).
- Whole-canvas layers (TileMapLayer, a Node2D pinned at World origin) can NOT y-sort.
  Hand-drawn structures are therefore painted as **per-cell Sprite2D nodes**, each
  anchored at its tile center with `z_index = int(global_position.y / TILE_SIZE)`.
- Shadows: `Global.make_shadow_sprite(texture, offset, scale, alpha)` — soft ellipse,
  `z_index = -1` (above ground layer, below world sprites). Trees use
  `shadow_base.png` scaled `0.55/0.22` at offset `-7.0`.
- Structure resources (`GeneratedStructure`) are auto-loaded from
  `STRUCTURES_DIR`, filtered to `spawn_world == "overworld"`, round-robined per chunk.
- Godot 4.6 gotcha: `GridContainer` has NO `alignment` property (no
  `GridContainer.ALIGNMENT_CENTER`) — only `BoxContainer` subclasses do. Don't
  use it on grids.

## Cave entrances (overworld)

- `sprites/cave/large_cave_entrance.png` is 342x256 px = 11x8 tiles (last column
  22 px, partial). Rows 0-1 are empty sky; rock is rows 2-7; the dark cave mouth is
  row 7, cols 3-5. `large_cave_entrance.tres`: `tile_width = 11`, `tile_height = 8`,
  `door_rect = Rect2i(3, 7, 3, 1)`.
- Placement (`world.gd:_place_cave_entrance_structure`): search a 5x5 offset grid
  around the ideal anchor for a valid footprint (water/trees veto), claim chunks,
  then spawn per-cell sprites. Returns
  `{"door_tile", "world_rect", "door_rect", "highlight_cells", "root"}`.
- Collision is per-cell opaque-pixel bounding boxes (`_cell_solid_rects`), only on
  present pixels — the player slides along the rock's real shape. Door cells stay
  solid: entry is click + confirm, not walk-through.
- `CavePortal` (invisible) supplies the proximity Area2D, the highlight, and the
  confirm dialog. `set_interact_rect` sizes the area to the whole structure;
  `set_door_rect` sets the door rect so `_draw()` highlights ONLY the dark mouth
  (yellow `C_DOOR_HIGHLIGHT` outline + faint fill), and only while the player is near.
- Optional hand-painted highlight: a `GeneratedStructure.highlight_mask` texture
  of exactly `tile_width x tile_height` pixels (one pixel per cell) replaces the
  door_rect highlight. Painted (alpha > 0.5) pixels become highlight cells —
  world.gd passes them as `highlight_cells` rects, and `CavePortal._draw_cell_highlight`
  fills them and outlines only the blob's outer boundary. Priority: mask > door_rect > whole rect.
- Ground the rock: `_paint_cave_base_ground` replaces the U-ring of ground tiles
  (row below the structure + the two cells flanking its bottom row) with the
  `sprites/cave/cave_base.png` tile (32x32 flat dark tile), registered lazily via
  `_get_cave_base_ground_src`. Skips water cells.

## Combat / swords

- `ItemData.is_sword` gates grass cutting (`world.gd:_try_cut_grass_with_sword`).
- `ItemData.sword_level` drives both scaling rules:
  - `sword_damage()` = `sword_level + 3` (LV1 = 4, +1/level, uncapped).
  - `sword_slash_radius()` = `mini(2, (sword_level - 1) / 3)` — vertical column
    centered on the tile in front: LV1-3 = 1 tile, LV4-6 = 3 (center + 1 above +
    1 below), LV7+ = 5 (capped at 2 each side). Damage keeps scaling past the cap.
- The slash column is screen-vertical (`center + Vector2i(0, r)`), replacing the
  old fixed 3-wide horizontal arc. No mob-HP system exists yet — damage is only
  a number for future combat to read.

## Working style

- NEVER commit unless the user explicitly asks.
- No Godot binary is on PATH — GDScript is validated by careful review, not a
  parser. Let the user run the game to test.
- This model cannot view images. To inspect a sprite's geometry/colors, analyze
  pixels with PowerShell `System.Drawing` (decode dimensions, alpha, per-pixel
  colors) instead of asking to "look" at the art.
- Match the existing file's comment style (boxed `# ── section ──` headers) and
  keep per-change rationale in comments.
