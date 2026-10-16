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

- **"Caves" ALWAYS means BOTH large caves AND pixie caves** unless the user
  explicitly says "large caves only" / "pixie caves only". So any cave fix must
  cover `cave_world.gd` + `pixie_cave_world.gd`, and anything driven through
  `CavePortal` (which both entrance types share) or the cave entrance
  structures already does.
- `TILE_SIZE = 32` everywhere. `GeneratedStructure.TILE_PX` is the structure-grid
  pixel size (also 32).
- World rendering is layered in `world.gd`:
  - `ground_layer` (TileMapLayer) has `z_index = -300` so all world sprites sort above it.
  - `water_layer` cells checked via `water_layer.get_cell_source_id(cell) != -1`.
- Y-sorting: any world-facing node gets a quantized `z_index = int(y / TILE_SIZE)` so
  each row sorts correctly against the player (player walks behind the row above, in
  front of the row below). Player origin is at chest height:
  `z_index = int((global_position.y + 23.0 + 16.0) / 32)` (see `player.gd`).
- Hitboxes: the player's `PlayerCol` is the feet box `RectangleShape2D(20, 12)`
  at `(0, 17)` (below the chest-height origin). Placement's
  `_cell_blocked_by_player()` mirrors it (20x12 at y 17) in all three worlds —
  keep in sync. Placed blocks (`PlaceableBlock.tscn`) use a **single solid
  `RectangleShape2D(32, 32)` at `(0, 0)`**. Cave gates: the door cell stays
  walkable at the bottom so the player can step into the doorway, but its **top
  half** is a solid box so they can't pass through it
  (`world.gd:_spawn_cave_entrance_nodes`). (History: blocks used to be a
  conditional U-shape — a bottom strip `(32, 16)` at `(0, 8)` + `(4, 32)` side
  walls at `x = ±14`, enabled only when a block sat above/below/diagonally; that
  left the upper half open so the player slipped into a block, so it became the
  solid tile. `PlaceableBlock.refresh_u_collision()` is now a no-op, kept only so
  the worlds' `_refresh_neighbor_u_collision(cell)` calls still work.)
- Bonfire (`bonfire.tres` + `Bonfire.tscn` + `scripts/bonfire.gd`, which
  `extends "res://scripts/placeable_block.gd"`): a placeable block that sets the
  player's respawn point. It joins the `"Bonfire"` group (minimap green marker),
  calls `Global.set_spawn_point(pos)` on placement (deferred — the world assigns
  the position after `add_child`), and `Global.clear_spawn_point()` on break if
  it was the active one. It sets the respawn **only in the overworld**
  (`world.is_overworld()`; caves/dungeons return false there, so a cave bonfire
  is just a light/block — its coords are structure-local and invalid for the
  overworld respawn). `Global._get_respawn_position()` still calls
  `get_world_spawn_position()` FIRST so the player exits any cave/dungeon, then
  prefers the bonfire. Any placeable item needs a non-empty `place_scene_path`
  or it can't be placed at all.
- Floors & doors (`ItemData.is_floor` / `is_door`, handled in
  `placeable_block.gd`): a **floor** is walkable (its `StaticBody2D/CollisionShape2D`
  is disabled) and renders as ground at `FLOOR_Z = -200` — the world sets that
  z at placement/restore (`world.gd`) so the block's deferred fallback can't
  lose the race with the world's y-sort z-assign. **`world.gd:_update_block_sort()`
  must SKIP floors** (and restore them to `FLOOR_Z`) — otherwise the tile the
  player stands on gets raised to `player_z + 1` and covers the player. A **door**
  swaps between `door_closed_sprite`/`door_open_sprite` on a **left-click**
  (SHIFT+click mines it instead), toggles its collider (closed = solid, open =
  passable), and **rotates** its node so its FRONT points the way the player
  faces (`_door_rotation_for()`; the 32x32 art is front-facing at rotation 0, so
  the front normal is "south": south = 0, north = PI, east = -PI/2, west = +PI/2).
  Facing + open/closed persist via `get/set_door_save_data()`.
  **Every `PlaceableBlock` exposes `get/set_door_save_data`, so both MUST no-op
  for non-doors** (guard on `item_data.is_door`) and the world only saves/restores
  the `"door"` entry for actual doors. Otherwise a restored FLOOR runs the door
  path, which re-enables its collider — "floor blocks have collision after
  restart".
- Housing (`world.gd`, overworld only): a "room" is a 4-connected region of
  **floor** cells enclosed by player-placed boundary blocks (walls + doors).
  `_is_boundary_block()` = placed ∧ not natural ∧ not floor. A room is VALID iff
  **sealed** (no non-boundary neighbour) ∧ **≥1 door** on the boundary ∧ interior
  bounding box ≥ 3×3. `housing_rebuild_around(cell)` runs on every
  place/break (handles merges/splits); `housing_rebuild_all()` on save-restore;
  `housing_is_valid_room_cell()` gates the ambient no-spawn director; the count
  drives the `build_shelter` mission (goal 1).
- Indoor dim: `Global.player_indoors` (set by `world.gd:_update_player_indoors()`
  every ~0.2s from `housing_is_valid_room_cell()`) makes the overworld's
  DayNightCycle (`day_night_cycle.gd`) multiply its ambient colour by
  `INDOOR_DIM` (0.72, eased) so standing in a valid house reads as "roofed".
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

## UI scaling (STANDING RULE — applies to every new UI / UI change)

**Every in-game UI and text MUST respect the global UI scale setting.** If asked
to add a new UI (or change one), scale it from the start — never hardcode px or
font sizes. The setting is Small/Medium/Large in the pause menu
(`pause_menu.gd`, values `0.75 / 1.0 / 1.5`) which writes `Global.ui_scale` and
emits `Global.ui_scale_changed(scale)`.

Convention (see `inventory_ui.gd`, `crafting_menu.gd`, `lua_editor_ui.gd`,
`pause_menu.gd`, `knowledge_altar.gd`, `quiz_altar.gd`):
- At the top of the build function: `var s: float = Global.ui_scale`.
- Multiply EVERY hardcoded size by `s`: fonts
  (`add_theme_font_size_override("font_size", int(13 * s))`), panel/slot/icon
  min-sizes, paddings, margins, separations, border widths, radii.
- Make it update LIVE: connect `Global.ui_scale_changed` (guard with
  `is_connected`) to a handler that rebuilds/re-scales the UI, and rebuild only
  where it already exists/is visible (preserve open state).
- World-space overlays that draw in `_draw()` (name labels, damage numbers,
  guide arrows, break bars — `Global.draw_break_bar` is already scaled) read
  `Global.ui_scale` live at draw time.
- Don't scale gameplay values — only visual sizing.

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

## Mobs

- **Pathfinding is REQUIRED for every mob.** A mob must route AROUND obstacles:
  trees, placed blocks, cave walls, and blocks the player drops in front of it
  *while it is moving*. Walking straight at the player and stalling on the
  first obstacle is a bug (the Headless Fish does exactly this today — it gets
  stuck when the player places blocks). Follow the `worm.gd` / `lua_npc.gd`
  pattern: probe a short ray ahead (`_ray_clearance` / `_path_is_clear`), then
  try a spread of reroute angles (`REROUTE_ANGLES_DEG`) and COMMIT to the best
  open direction for a short window so it doesn't dither on corners. Obstacles
  are `StaticBody2D` on physics layer 1.
- **Movement must look like FLYING, never teleporting.** A mob may change its
  chosen route freely, but its actual motion has to be smooth: bound the turn
  rate and speed, and NEVER assign `global_position` to "unstick" or reposition
  a mob (the player has an unstuck teleport; mobs must not). Steering forces
  added on top of a base velocity must be speed-capped, otherwise the combined
  velocity spikes. `HeadlessFishAI` is the reference: `_find_clear_dir` picks
  the closest open path toward the player, then `TURN_RATE`/`FLIGHT_SPEED_CAP`
  rotate the heading into it so the fish banks around obstacles. Flying mobs
  use `motion_mode = CharacterBody2D.MOTION_MODE_FLOATING` (GROUNDED's
  floor/wall snapping pops them around geometry, which reads as teleporting).
- Any walking mob re-sorts every frame:
  `z_index = int(global_position.y / TILE_SIZE)`.
- **Contact damage**: poll each frame with a per-mob cooldown — never rely on
  `body_entered` alone (it fires once and won't fire again while overlapping).
  Canonical shape (`_try_attack_player(delta)` in wolf/pixie/worm/fish):
  early-out on `COMBAT_DATA.damage <= 1.0` → decrement `_attack_cooldown` →
  range check → `Global.damage_player(...)`. Keep cooldowns consistent
  (wolf/pixie 1.0s, worm 1.2s); a 5.0s outlier reads as "it never damages
  twice". Player i-frames are `player.gd` `INVINCIBILITY_MS = 300` (0.3s) — if
  a mob looks like it only hits once, check the MOB's cooldown, not i-frames.
- `_try_attack_player()` must sit on a code path the active state actually
  reaches. `_physics_process` early-returns per state (the worm's call was in
  the IDLE-only tail, so an emerged worm never dealt contact damage).
- Spawn rules live in `resources/mobs/*.tres` (`MobCombatData`:
  `spawn_during_day`/`spawn_during_night`, biome flags, `spawn_weight`,
  `behavior` HOSTILE/PASSIVE, flee tuning). The overworld runs an **ambient
  spawn director** (`world.gd`): a continuous, CAPPED population spawned in a
  ring 18–44 tiles around the player (`AMBIENT_RING_*`), topped up every tick
  (`AMBIENT_DAY/NIGHT_INTERVAL`) up to `AMBIENT_DAY/NIGHT_CAP`, with a night
  ramp via `_night_progress()`. Period flips fill straight to the new cap
  (`_on_night_started`/`_on_day_started`). Mobs beyond `AMBIENT_DESPAWN_TILES`
  for `AMBIENT_STRAY_LINGER` are recycled (`_despawn_strays`), and the older
  30/15/5-min zone timer now runs over the whole `"Mob"` group. PASSIVE mobs
  flee on `take_hit` via `FleeBehavior` (see `_maybe_flee`). Never teleport.

## Pause & input

- Opening any UI (`Global.open_ui()`) sets `get_tree().paused = true`. A
  **pausable** node (the player, blocks — default `PROCESS_MODE_INHERIT`) does
  NOT receive `_input`/`_process`/`_physics_process` while paused. So a mouse
  RELEASE that happens while a UI/dialog is open is never seen, and any
  hold-state latched on press (`player.gd` `_attack_held`, `placeable_block.gd`
  `_mouse_held`) stays stuck — resuming the swing loop / block break forever
  once the UI closes. Reconcile the latch against `Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)`
  on the first unpaused tick (`_tick_attack_hold` / `_process`) so a lost
  release can't leave it latched. The cave/portal confirm dialog also pauses
  (`cave_portal.gd` `Global.open_ui()`), so this bites on scene changes too.
- `SceneTree.create_timer(t)` defaults to `process_always = true`, so transient
  effects that free themselves on a timer (`sword_swing_effect.gd`) still
  despawn while the tree is paused.

## Working style

- NEVER commit unless the user explicitly asks.
- Godot 4.6 console binary:
  `C:\portable_programs\Godot_v4.6-stable_win64.exe\Godot_v4.6-stable_win64_console.exe`.
  Validate every GDScript/resource change headlessly:
  `& "<console exe>" --headless --editor --quit --path "<SandEEAlpha>"` then grep
  the output for `SCRIPT ERROR|Parse Error|Compile Error|Failed to load`.
- Functional tests: write a temporary `_tmp_*.gd` + `_tmp_*.tscn` (root node with
  the script attached) inside `SandEEAlpha/`, run
  `& "<console exe>" --headless --path "<SandEEAlpha>" res://_tmp_x.tscn`, then
  DELETE the pair plus any generated `.uid`. Autoloads (`Global`, singletons) are
  NOT available under `--script` — run a real scene instead. Use a
  `CharacterBody2D` (not `Node2D`) as a stub player so physics/RID queries work.
- This model cannot view images. To inspect a sprite's geometry/colors, analyze
  pixels with PowerShell `System.Drawing` (decode dimensions, alpha, per-pixel
  colors) instead of asking to "look" at the art.
- Match the existing file's comment style (boxed `# ── section ──` headers) and
  keep per-change rationale in comments.
