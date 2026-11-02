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
* cave generation edges: the first Pixie Cave is pixie-free and later ones
  spawn normally, every Pixie Cave is at least 36x26 tiles with at least three
  7x7 rooms, both cave types keep four solid border layers, and both cave camera
  bounds include 20 tiles of wall padding so edge framing does not expose the
  generated-grid edge
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
* Algorithmica editor templates: ready-to-run station/furnace examples behind
  the TEMPLATE button, and the guided furnace lesson opening with
  `print("Algorithmica ready")` instead of a commented snippet
* color output block RGB/HEX mode switching, display conversion, edits,
  malformed-input rejection, preview updates, quantity/program-code stability
* Knowledge Altar archive pagination: empty/single/multi-page, boundaries,
  and live archive refresh when knowledge unlocks while open
* Knowledge Altar interaction: only the altar under the cursor opens, opening
  alone never learns, and Continue emits the explicit read event the tutorial
  uses instead of trusting an already-learned entry
* overlapping interactable disambiguation: nearest Automatica station/robot and
  nearest point-and-click target win, and camp placement reserves the player's
  tile ring plus both guides' footprints
* cave/Pixie underfoot drop pickup and quantity preservation
* full-inventory pickup attempts warn once per approach instead of replaying
  the inventory-full sound every frame, and the drop is collected automatically
  when inventory space opens
* cave/Pixie mining collision blocker while a tile is visually hidden
* shared player mining-time formula with a minimum break time: iron/diamond
  pickaxes no longer one-tap every low-tier block, while harder blocks still
  take longer
* held-button chain mining: placed blocks and cave walls/ores that come under
  the cursor continue breaking without a new click, and stop on release
* Desert Worm water-boundary movement guard
* complete ore smelting coverage: every base/crystal/diamond ore has a valid
  recipe, is selectable by the timed furnace cook, and smelts through the real
  furnace with exact input/fuel consumption, failed/full-output atomicity and
  furnace save/load round-tripping
* data-driven iron smelt mission tracking and one-per-placement mission event
* shared held-item damage display (sword tier or 1.0 token, never false zero)
* updated cactus spawn interval/clearances, and Desert Worm 5-10 cactus loot
  with one-bundle-per-defeat and no loot from cleanup/despawn paths
* fish display names (Yellow Carp, Anglefish, Eelfish, Scuttlefish) with stable
  scripting ids, Automatica naming, and legacy `lua` item id preservation
* Headless Fish one-raw-fish drops and no loot from despawn cleanup
* rare dungeon-chest generation in eligible bonus rooms, deterministic
  Automatica/food loot, dungeon state persistence, and Large/Pixie cave
  rare-chest placement snapshots
* combined inventory/chest drawer: icon-labelled Chest tab under the lifted
  player grid, drag in/out in both directions, delete-from-chest, and the
  bottom-right delete target inside the inventory panel
* minimap Automatica sprite icon/legend plus live Crafting Station, Furnace
  and Color Crafter markers, and tap/click travel to Automatica or dungeon
  portal icons on the expanded overworld map
* Hitman miniboss two-room generation, enlarged sprite/health, single spawn,
  defeat completion and exit activation
* the optional extra-dungeon path (exercised with a synthetic mission) using no
  Knowledge Altar and two functional Quiz Altars
* 20 unique side missions, locked-before-progression behavior and post-unlock
  progress tracking
* full mission log: every visible main, dungeon and side mission in
  encyclopedia-style expandable rows with task, purpose, lesson and rewards,
  active groups first, completed missions collected at the bottom, plus a
  two-side-mission live tracker limit
* Py-San in-dungeon explanations for where the Knowledge and Quiz Altars are
  and what each lesson is for, with matching altar atlas art on the world and
  minimap
* blank player-facing Lua/Python dungeon starter code with validation intact
* Quiz Altar auto-pause and post-completion dungeon exit placement beside the player
* dungeon route guidance: every run draws dotted floor circles to the Knowledge
  Altar first and then the Quiz Altar (boss finale points at the Miniboss and
  exit), while main-dungeon Quiz Altars stay locked behind a gold padlock until
  their linked knowledge entry is learned
* overworld next-dungeon guidance: route dots, a labelled marker and a compass
  alternate the Lua/Python tracks from the last cleared dungeon, and every
  dungeon entrance gets a pulsing minimap halo with the recommended next one
  emphasized in teal; dungeon maps pulse their current objective
* Escape/back closing the top menu overlay and cancelling (not confirming) a
  destructive dialog
* Android/touch safety: event-position UI hit-testing, safe-area offsets for
  modal/scroll roots, physical-pixel virtual-keyboard height conversion, a
  scroll-safe sign-in form whose fields stay above a simulated keyboard,
  modal cancellation of PNC and held touch gestures, touch-ID bridge
  tracking/release, hotbar/joystick clearance checks, explicit BUILD/SPRINT/
  INTERACT UI hit-testing with a short world-click guard, and no Android tap or
  press-and-hold tooltip popups
* mobile HUD: the approved A/B/C/D action matrix (BUILD stays right with the
  fixed joystick, moves into the joystick slot when PnC hides it, and SPRINT
  disappears with auto-sprint), a single-line blue/yellow star total beside
  PAUSE, a raised mission tracker with no duplicate star header, and thick
  HP/stamina bars labelled with current / max values
* mobile multi-touch: secondary fingers directly trigger BUILD/SPRINT/INTERACT
  and hotbar slots without stealing the held joystick touch or relying on the
  joystick's GUI mouse focus
* cave entrance prompts use the real cave type: regular entrances say
  "Large Cave Entrance" and pixie entrances say "Pixie Cave Entrance"
* cave/Pixie Cave/dungeon transitions: a scaled loading bar with distinct
  destination labels while the world swap is prepared, and pause-safe cleanup
  so tutorial dialogue cannot leave the overlay stuck on "Ready"
* title branding: website cartridge-tree mark, app-icon colour palette and
  white/green SandEE wordmark (the icon's S is not repeated), with Py-San and
  LUA flanking the logo on both the sign-in and main-menu screens; a 1-in-5
  easter egg replaces the E run with `SandEEEEEEEEEEEEEEEEEEEEEEEEEEEE`
* global autosave notification: a top-centre "Autosaving..." pill with a
  circular spinner appears during every save, across the overworld, caves,
  dungeons, editors and menus, with a minimum on-screen time
* Minecraft-style ambient BGM: menu, overworld day/night, snowy, shelter, cave
  and four randomized dungeon variations, with fade-in/out and quiet gaps
  between tracks (no immediate repeat)
* dungeon deaths respawn at the dungeon's generated entrance room instead of
  exiting to the overworld; cave and overworld deaths still use the world spawn
* PNC treats the object's own proximity area as already-in-range, so tapping a
  nearby chest/station/furnace/door opens or mines it immediately instead of
  pathing into the object
* Automatica tutorial mission lesson: after building the line, Py-San lists the
  first active Automatica missions and explains the tracker/log, while the HUD
  temporarily shows only the mission tracker and star total; opening the full
  mission log verifies the lesson before the normal HUD returns
* GUIDED START objective card is horizontally screen-centred (and shrinks
  around that centre on narrow screens so it stays clear of the top-right HUD)
* dungeon Quiz Altar HINT shows the answer only as ghost/placeholder text in
  the code editor; the player must type it themselves, and Hint/Next never
  overwrites their code
* every Bestiary/dungeon enemy uses the same autohide health bar as legacy
  mobs, positioned above tall 48/64px sprites and their upward offsets instead
  of being hidden behind the animated sprite
* map previews: the minimap and world-waypoint overview include player-placed
  blocks using each block's item colour, and Automatica stations show their
  custom names on both previews
* PC floating control guide: bottom-right WASD/Shift (Shift only while
  point-and-click is on) beside the merged contextual LMB chip + Ctrl build,
  dynamic USE/MINE/ATTACK/CHOP/MOVE/INTERACT/CHASE labels, contextual Shift+
  DESTROY, hover/press highlights, focus-loss reset, F1 hide/show, live
  bindings, and suppression under modals, fullscreen HUD screens and text fields
* mobile point-and-click: taps drive moves and interactables on Android, a
  pickaxe-held tap opens a nearby crafting station/furnace instead of mining it,
  automatic sprint stays configurable while PnC is off, manual SPRINT remains
  visible in joystick mode, and the disabled INTERACT button keeps its circular
  style instead of falling back to a rectangle
* world-load input state: a build-mode toggle left on from the title/menu or
  loading screen is cleared before control is handed back, so it cannot make
  point-and-click move clicks place blocks instead
* stat crystals: Life/Stamina hotbar use raises maximum and current HP/stamina
  by 10, caps at 500 HP / 1000 stamina, a 10% total mob drop split 50/50, one of
  each on a first dungeon clear, and per-world save/load with legacy saves
  defaulting to base stats
* friendly Wisp companion: Game-owned singleton across cave/dungeon swaps,
  Mob-group exclusion and non-blocking collision, one cached-texture light,
  boosted cave/Pixie-Cave light profiles, the light switched off inside
  dungeons, smooth follow with obstacle steering, distance/stuck recovery,
  death/respawn hiding, and duplicate-instance cleanup
* ambient birds: both approved 4-frame wing strips, day/night finch/kite
  species selection, and the absolute above-world draw layer
* Automatica API audit: every documented helper/function executes through the
  Lua preamble plus the Rust bridge, station globals are readable, queued
  build helpers place once per captured slot, and the Algorithmica
  station/furnace references match both Python host bases
* guided Automatica lessons: the camp robot receives exactly 32 Wood in BUILD
  SLOT 1 for a straight build_line run, the next lesson grants one additional
  Automatica and Wooden Sword exactly once, and the flow requires that Wooden
  Sword in the robot's TOOL slot plus the real `combat_mode(true)` state
* post-lesson explanations: Automatica and Algorithmica each add a one-time
  two-box explanation after their first successful build/run, and both resume
  correctly after save/reload without replaying the lesson briefing
* Automatica combat swings are independent: robots use their own randomized
  attack cooldowns and are never triggered by the player's swing
* combat Automatica projectile defence: nearby flare/Hitman bolts heading for
  the robot or its escorted player are auto-parried through the same `parry()`
  path as the player's sword, with a short cooldown and no non-combat parries
* Automatica hunting uses the shared hostility check, so it now targets both
  legacy mobs and the newer Bestiary/dungeon enemies
* combat mode is reversible: combat followers expose a click target for the
  editor, PnC can interact with the floating robot, and `combat_mode(false)` or
  EXIT COMBAT returns it to its blue station form
* Automatica Management rows show an explicit NORMAL/COMBAT mode badge beside
  the live action status and combat HP
* tutorial HUD gating: mission tracker/star total stay hidden for the whole
  onboarding (the Automatica mission lesson opts in temporarily), and tutorial
  camp structures reject break attempts until the tutorial is complete
* Automatica renaming is capped at 12 characters in both `rename()` and the
  editor's rename field, with trimmed input and old saves clamped on load
* code-only Algorithmica: the crafting station exposes the Python editor but
  not the redundant recipe picker, item-input slot or output/color inspector;
  `take_output()` remains the collection path
* Algorithmica item suggestions hide dev-only blocks and use a non-focusable
  popup, so Backspace/Delete keep editing the code while the list is open
* Automatica editor layout matches Algorithmica: CODE/INVENTORY/ENCYCLOPEDIA
  tabs, a TEMPLATES column, the program log inline under the code editor, and
  the same panel proportions/header structure
* Automatica reference toggle is explicit in the header, and closing/reopening
  the station always returns to CODE instead of restoring the encyclopedia tab
* code safety: obvious non-terminating Lua/Python loops are rejected before
  execution, with break/return-aware checks and string/comment stripping
* mission-complete toast: a persistent top-centre notification for Lua, Python,
  Automatica, Algorithmica and side missions, queued and stacked below autosave
* crafting requirements: every ingredient row shows its item name in both the
  inventory crafting tab and the crafting-station sidebar, with a data-driven
  where-to-get hint on PC hover and Android press-and-hold
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
* cloud deletion tombstones: deleting a world emits its stable UID/checksum,
  queued offline deletions persist per account, remote tombstones delete the
  matching local copy instead of re-uploading it, and stale cloud rows are
  hidden from the Cloud Saves list
* WASD/tap-to-control movement parity: all eight directions, normalized
  diagonal speed, sprint/stamina state, snowstorm slowdown, movement
  animations, wall collision, and cancellation on UI/mode/focus changes
* point-and-click wall handling: a solid point with no walkable approach or no
  A* route is rejected immediately instead of walking into it until the stuck
  timeout
* point-and-click interaction: interactable objects resolve to their owning
  node, PNC walks to one-block range of the object origin/approach point, then
  opens or interacts directly; synthetic replays cannot make the player swing,
  and a real chest sprite resolves correctly
* PNC tap latency: lazy (line-of-sight first) pathfinding and spatial tree
  canopy lookup without repeated whole-world scans
* PnC usable-item click routing: food, crystals, rod, hoe and buckets use the
  held item instead of issuing move/interact orders; one use per press, normal
  PnC movement resumes with non-usable tools
* Android release configuration: package id/version/INTERNET permission, GLES3
  compatibility renderer, responsive canvas scaling and first-touch UI
  emulation
* global display settings: FPS limit options and Unlimited mapping on both
  platforms, nearest-option sanitization, Engine.max_fps application, and a
  desktop-only VSync control
* shared settings persistence: main-menu and in-game panels save master/music/
  SFX volume, camera zoom, pause-on-inventory and quest-background choices to
  settings.cfg; fresh installs default to 90% master / 70% music / 80% SFX
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
* opening-tutorial HUD reveal: movement starts with only essential controls,
  tools/hotbar (including its nested canvas) appear at the tree lesson,
  map/missions/stars at the dungeon lesson, and the full normal HUD becomes
  permanent from Automatica onward; completion is saved and later tutorial
  lessons never re-hide the HUD
* tutorial travel briefings: Py-San explains dungeon, cave, Pixie Cave,
  waypoint, camp-return and Algorithmica destinations before any tutorial
  relocation, and the GUIDED START card hides while inventory/station panels
  are open so it cannot cover their tabs
* tutorial cave ore target: natural ores are limited to the entrance area, and
  a nearby wall is converted into a mineable ore when the layout has none close
  enough, so the lesson never points across the cave
* post-onboarding settings tour: opens the real pause/settings panel, walks
  category and setting controls with highlight-only targets (no pointing
  arrow), NEXT/SKIP controls, scroll-safe targets, and skips missing
  desktop-only/optional rows; the GUIDED START card anchors to the top-left and
  reserves the top-right star/PAUSE/mission column so it cannot overlap them
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
* Lua/Python dungeon quiz audit: all remaining questions across both language
  tracks open with readable question text at scroll top and a panel inside the
  mobile viewport; the Lua File I/O compiler question has a real expected
  output, the first Python dungeon no longer contains a multiple-choice
  question, and the tutorial highlights the answers without a label covering
  the question
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
