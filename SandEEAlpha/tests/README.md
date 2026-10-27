# QA regression suite

Run from the repository root:

```powershell
tools\run_qa.ps1
# or
tools\run_qa.ps1 -Godot "C:\path\to\Godot_v4.6.3-stable_win64_console.exe"
```

The suite is **offline**: it never contacts Supabase. It exercises:

* mission registry/order (retired wolf mission, final diamond missions)
* save/load and retired-mission migration, at-goal completion, mission version
* mission triggers (dungeon clear, learn entry, dungeon quiz run)
* pause/UI refcount and altar teardown
* dungeon-exit build-mode restore and focus release
* legacy-world leaderboard eligibility (before/after 0.9.3.0)
* dungeon generation across 12 seeds: room edge margins, trap clearance from
  rooms/spawn/narrow passages, two-hitman quiz cap, quiz-trap corridor openings
* dungeon camera padding math
* trap/flare/hitman damage constants **and actual damage application**
* safe-zone union, overlap removal, inclusive edge/corner protection, fast
  projectile segment crossing, projectile/enemy disintegration, no death/loot
* grass clearance around dungeon entrance spawn cells
* cave/pixie state round-trips (mined walls/ores, placed blocks, defeated
  pixies), visited-instance caching and same-instance re-entry, Cave A/B state
  independence, portal re-arming/monitoring after exit, and cave-state
  save/load persistence
* torch support rules in the overworld and caves (solid walls/blocks only;
  floors, torches and bonfires do not count), stale-connection refresh when
  cave walls/ore are mined or ore regenerates, isolated/connected/variant art,
  pickaxe/axe drops, normal-torch identity for connected variants, pickup, and
  full-inventory overflow leaving the drop on the ground
* offline main-menu **Go Online** button visibility versus the online
  leaderboard/cloud/account row
* sheep classified as passive/friendly for minimap and hostile-mob checks
* Algorithmica `craft_color(r,g,b,amount)`: registration/transpiler path,
  8-bit RGB validation, one-Cactus-per-block cost, output slot/stacking,
  insufficient-material atomicity, station save/load and full-inventory behavior
* color output block RGB/HEX mode switching, display conversion, edits,
  malformed-input rejection, preview updates, quantity/program-code stability
* Knowledge Altar archive pagination: empty/single/multi-page, boundaries,
  and live archive refresh when knowledge unlocks while open
* cave/Pixie underfoot drop pickup and quantity preservation
* cave/Pixie mining collision blocker while a tile is visually hidden
* Desert Worm water-boundary movement guard
* complete ore smelting coverage: every base/crystal/diamond ore has a valid
  recipe, is selectable by the timed furnace cook, and smelts through the real
  furnace with exact input/fuel consumption, failed/full-output atomicity and
  furnace save/load round-tripping
* data-driven iron smelt mission tracking and one-per-placement mission event
* shared held-item damage display (sword tier or 1.0 token, never false zero)
* updated cactus spawn interval/clearances, and Desert Worm 5-10 cactus loot
  with one-bundle-per-defeat and no loot from cleanup/despawn paths
* fish display-name fixes with stable scripting ids, Automatica naming and
  legacy `lua` item id preservation
* Headless Fish one-raw-fish drops and no loot from despawn cleanup
* rare dungeon-chest generation in eligible bonus rooms, deterministic
  Automatica/food loot, dungeon state persistence, and Large/Pixie cave
  rare-chest placement snapshots
* combined inventory/chest drawer: icon-labelled Chest tab under the lifted
  player grid, drag in/out in both directions, delete-from-chest, and the
  bottom-right delete target inside the inventory panel
* minimap Automatica/LUA marker colour and `LUA` legend constant
* Hitman miniboss two-room generation, enlarged sprite/health, single spawn,
  defeat completion and exit activation
* the optional extra-dungeon path (exercised with a synthetic mission) using no
  Knowledge Altar and two functional Quiz Altars
* 20 unique side missions, locked-before-progression behavior and post-unlock
  progress tracking
* blank player-facing Lua/Python dungeon starter code with validation intact
* Quiz Altar auto-pause and post-completion dungeon exit placement beside the player
* Escape/back closing the top menu overlay and cancelling (not confirming) a
  destructive dialog
* Android/touch safety: event-position UI hit-testing, safe-area offsets for
  modal/scroll roots, physical-pixel virtual-keyboard height conversion, a
  scroll-safe sign-in form whose fields stay above a simulated keyboard,
  modal cancellation of PNC and held touch gestures, touch-ID bridge
  tracking/release, and hotbar/joystick clearance checks
* ambient birds: both approved 4-frame wing strips, day/night finch/kite
  species selection, and the absolute above-world draw layer
* Automatica API audit: every documented helper/function executes through the
  Lua preamble plus the Rust bridge, station globals are readable, queued
  build helpers place once per captured slot, and the Algorithmica
  station/furnace references match both Python host bases
* code-only Algorithmica: the crafting station exposes the Python editor but
  not the redundant recipe picker, item-input slot or output/color inspector;
  `take_output()` remains the collection path
* quiz altar results: boxed compiler output, a top-right HINT button that
  auto-completes one question, 3/2/1 blue-star awards by hint count, the
  achievements/Done results screen, and Done returning to the overworld
* three-star dungeons: mission + clear + perfect-clear reward IDs, legacy
  clears defaulting to 3 stars, save/load of per-dungeon star awards, and
  three-star mission rows
* centralized topmost-first UI back stack for Escape/Android Back, including
  hidden/stale overlay skipping, one-key/one-layer deduplication and layered UI
  dismissal, plus real inventory, crafting, smelting, color-crafter,
  furnace-editor and pause-menu close paths
* stable per-world save UID/revision, legacy-save migration, and cloud-sync
  conflict classification (different world, newer cloud, equal-revision
  divergence, legacy metadata, newer local upload)
* WASD/tap-to-control movement parity: all eight directions, normalized
  diagonal speed, sprint/stamina state, snowstorm slowdown, movement
  animations, wall collision, and cancellation on UI/mode/focus changes
* point-and-click interaction: interactable objects resolve to their owning
  node, PNC walks to one-block range of the object origin/approach point, then
  opens or interacts directly; synthetic replays cannot make the player swing,
  and a real chest sprite resolves correctly
* PNC tap latency: lazy (line-of-sight first) pathfinding and spatial tree
  canopy lookup without repeated whole-world scans
* Android release configuration: package id/version/INTERNET permission, GLES3
  compatibility renderer, responsive canvas scaling and first-touch UI
  emulation
* global display settings: FPS limit options and Unlimited mapping on both
  platforms, nearest-option sanitization, Engine.max_fps application, and a
  desktop-only VSync control
* responsive UI metrics: desktop/phone scale floors and caps, aspect-independent
  short-edge sizing, compact-viewport modal clamping, and removal of the old
  per-save UI-scale preference
* biome-aware procedural houses/pillars: template loading, deterministic
  block-only layouts, house/pillar coverage for every biome, valid item/scene
  paths, footprint bounds, and save/reload removed-cell persistence
* tree canopy occupancy: full canopy/trunk footprint, grass/placement exclusion,
  scattered-crown spacing, and canopy cleanup when a tree is chopped
* waypoint network: approved sheet slicing at eight 10 fps frames, native
  5x4/6x5 dungeon entrance portals, the 3x3 temporary step-trigger waypoint, the
  5x7 tower footprint, stable temporary/permanent save rows, and world-map
  open/select/teleport-close behavior
* fullscreen safe-area map promoted above the HUD (gameplay HUD hidden while
  open), a top-right X close button, a rectangle-filling map, and a right-side
  vertical legend list including World Waypoint markers
* clickable world-tower facade/base with a soft floor shadow and shaded plinth,
  plus a teal recall beacon and white screen fade before waypoint travel
* tutorial direction aids and persistent skip: a player-following compass arrow,
  four inward tile-marker arrowheads, a safe-area top-right SKIP LESSON button,
  and the dialogue-signal to guide-skip flow advancing exactly one lesson
* short-screen pause menu: scroll-safe card at 640x360 with the bottom
  Help/Settings/Quit controls reachable inside the safe area
* pause Help & Documentation: nine complete categories (start, controls,
  survival, building/farming, crafting/machines, programming/automation,
  dungeons/Bestiary, maps/missions/saving, settings/troubleshooting), category
  switching, safe-area fit at 1152x648, 1024x600 cutout, 800x480, 640x360 and
  1920x1080, plus Back/Escape one-layer close behaviour
* contextual desktop cursors: all six approved 24x24 sprites imported, in-bounds
  hotspot, chest/crafting/Color Crafter/furnace/plain-click/waypoint/cave context
  mapping, headless disabling and the mobile-host guard
* overworld UI hit-testing: only registered CanvasLayer/top-level-Control roots
  are walked, never the ~40k-node world tree; hidden layers, dynamic layers,
  mouse-ignore controls and freed-root pruning are covered
* PNC tap-to-mine on mobile: synthetic mining holds are pushed in viewport-local
  coordinates and placed blocks resolve hover from the PNC world target, so
  Android canvas stretch cannot send the press to the wrong tile
* mission tracker clearance: the tracker starts below the live bottom edge of
  the top-right pause button instead of using a fixed offset that overlapped on
  mobile UI scales
* mobile altar modals: Knowledge and Quiz panels are capped to the usable
  viewport with an internal body/question scroll, responsive quiz editor/output
  and answer widths, and touch-scrollable panel surfaces
* Lua/Python dungeon quiz audit: all 80 questions across both language tracks
  open with readable question text at scroll top and a panel inside the mobile
  viewport; the Lua File I/O compiler question now has a real expected output
* account isolation: account UUID-scoped local world directories, encrypted
  owner/world-uid sidecars, transition markers, verified-account offline
  binding, cross-account load/list/upload guards, and Android backup/uninstall
  settings that require a fresh sign-in after reinstall
* automatic next-dungeon handoff after completion, Lua 11 -> 26 continuation,
  the 15-mission Lua / 10-mission Python main tracks, plus the two-room,
  enemy-free/hazard-free tutorial layout for the first Lua and Python dungeon
* per-language dungeon TileSets and interiors: 11 wall variants / 5 floor
  variants per theme, themed props, solid pillar bases, eight-frame sconce and
  medallion animations at 10 fps, and live local light flicker
* valid/invalid Lua and Python execution, Python runtime errors, and clear
  rejection of assignments to reserved GDScript type names such as `int`
* per-launch randomized Lua/Python dungeon title panoramas, shared by the
  sign-in and title screens and cycled at randomized 20-40 second intervals
* crash-log capture and backtraces

Notes:

* Pre-account flat `user://save_slot_N.json` files are deliberately left intact
  but are not listed or auto-imported: they have no verified owner and must not
  be attached to whichever account signs in first.

* Manual layout probes cover 800×600, 1024×768, 1152×648, 1280×720 and
  desktop 16:9; settings, pause menus, hotbar slots, the inventory modal
  (HUD hidden, fitted grid, tooltip routed to its detail sidebar) and the
  main-menu scroll layout remain inside the viewport.
* The suite intentionally triggers a GDScript division-by-zero and a
  `push_error` to verify runtime-error capture. Those `SCRIPT ERROR` lines in
  the console are expected.
* Godot currently prints `ObjectDB instances leaked at exit` (3 pre-existing
  base-object instances) and therefore returns a nonzero process code even
  when every check passes. `QA_RESULT: N/N passed, 0 failed` is the test
  result; the leak warning predates the cave/pixie tests and is tracked
  separately from gameplay regressions.
* It uses one free save slot and deletes it afterwards. No existing world is
  modified.
* Live Supabase checks (stars, cloud limit, ledger) are documented in
  `supabase/README.md` and are intentionally not part of this offline suite.
