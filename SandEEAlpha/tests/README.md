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
* minimap Automatica/LUA marker colour and `LUA` legend constant
* Hitman miniboss two-room generation, enlarged sprite/health, single spawn,
  defeat completion and exit activation
* extra dungeons with no Knowledge Altar and two functional Quiz Altars
* 20 unique side missions, locked-before-progression behavior and post-unlock
  progress tracking
* blank player-facing Lua/Python dungeon starter code with validation intact
* Quiz Altar auto-pause and post-completion dungeon exit placement beside the player
* Escape/back closing the top menu overlay and cancelling (not confirming) a
  destructive dialog
* centralized topmost-first UI back stack for Escape/Android Back, including
  hidden/stale overlay skipping, one-key/one-layer deduplication and layered UI
  dismissal, plus real inventory, crafting, smelting, color-crafter,
  furnace-editor and pause-menu close paths
* stable per-world save UID/revision, legacy-save migration, and cloud-sync
  conflict classification (different world, newer cloud, equal-revision
  divergence, legacy metadata, newer local upload)
* Android release configuration: package id/version/INTERNET permission, GLES3
  compatibility renderer, responsive canvas scaling and first-touch UI
  emulation
* valid/invalid Lua and Python execution, Python runtime errors
* crash-log capture and backtraces

Notes:

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
