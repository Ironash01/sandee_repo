# Side mission replacement proposal: Automatica + Algorithmica

**Status:** design proposal only. No mission definitions, tracking hooks, UI, saves, or
game code have been changed.

The current 20 side missions are world/combat/collection tasks. This proposal replaces all
20 with **30 automation-focused side missions**: 12 Automatica (Lua robot), 12 Algorithmica
(Python stations/furnaces), and 6 hybrid factory missions that require both systems.

All missions use existing items, stations, tools, and the existing yellow side-mission
star. They unlock after the main dungeon track, just like the current side missions, and
the tracker continues to show three active side missions at a time.

## Automatica — 12 missions

| # | Mission | Objective | Key functions | Goal | Tier |
|---:|---|---|---|---:|---:|
| A1 | **Boot Sequence** | Successfully run any Automatica program. | any Automatica call | 1 program | 1 |
| A2 | **Nameplate Protocol** | Give an Automatica a custom name. | `rename()` | 1 robot | 1 |
| A3 | **Timber Routine** | Chop 10 trees in one program run. | `chop_trees(20)` | 10 trees | 1 |
| A4 | **Full Work Cycle** | Complete one full chop → deposit → return cycle. | `auto_work()` | 1 cycle | 2 |
| A5 | **Chest Logistics** | Withdraw 16 Wood from a chest, then print the chest contents. | `withdraw("Wood", 16)`, `chest_contents()` | 16 Wood + 1 read | 2 |
| A6 | **Line Worker** | Place a 12-block line. | `build_line()` | 12 blocks | 2 |
| A7 | **Foundation Frame** | Place a hollow 6×6 foundation frame. | `build_rect(..., false)` | 20 blocks | 2 |
| A8 | **Rune Ring** | Build a ring of at least 20 blocks. | `build_ring()` or `build_circle()` | 20 blocks | 3 |
| A9 | **Pattern Practice** | Build a 16-block wave fence and a 12-step staircase in one program. | `build_wave()`, `build_stairs()` | 28 blocks | 3 |
| A10 | **Spiral Shrine** | Build a spiral of at least 30 blocks. | `build_spiral()` | 30 blocks | 3 |
| A11 | **Miner Unit** | With a pickaxe equipped, mine 10 stone blocks with the robot. | `mine("stone_block")` | 10 blocks | 3 |
| A12 | **Combat Protocol** | Enter combat mode with a weapon equipped and defeat 3 hostile mobs with the robot. | `combat_mode(true)` + robot attacks | 3 kills | 4 |

## Algorithmica — 12 missions

| # | Mission | Objective | Key functions | Goal | Tier |
|---:|---|---|---|---:|---:|
| G1 | **Python Primer** | Successfully run any Algorithmica program. | any station/furnace call | 1 program | 1 |
| G2 | **Recipe Reader** | Print the selected recipe and current output count at a crafting station. | `get_recipe()`, `output_count()` | 1 read | 1 |
| G3 | **Plank Factory** | Select Planks, craft 16, and collect the output. | `set_recipe("Planks")`, `craft(4)`, `take_output()` | 16 Planks | 1 |
| G4 | **Batch Logic** | Craft 16 of one recipe in a single program. | `craft()` in a loop | 16 items | 2 |
| G5 | **Output Audit** | Read output item/count before and after crafting, then collect the result. | `output_item()`, `output_count()`, `take_output()` | 1 audit + craft | 2 |
| G6 | **Color Starter** | Craft 2 red blocks and collect them. | `craft_color(255, 0, 0, 2)`, `take_output()` | 2 blocks | 2 |
| G7 | **Color Wheel** | Craft 2 red, 2 green, and 2 blue blocks in one program. | `craft_color()` × 3 | 6 blocks | 3 |
| G8 | **Palette Stockpile** | Craft 16 colored blocks total. | `craft_color()` | 16 blocks | 3 |
| G9 | **Furnace Primer** | Load iron ore and fuel, smelt 5 bars, and collect the output. | `feed("Iron Ore", 5)`, `fuel("Wood", 5)`, `smelt(5)`, `take_output()` | 5 Iron Bars | 2 |
| G10 | **Furnace Status** | Print input and fuel names/counts, then smelt 4 iron bars. | `input_name()`, `input_count()`, `fuel_name()`, `fuel_count()`, `smelt(4)` | 4 Iron Bars | 3 |
| G11 | **Iron Line** | Smelt 10 iron bars in one program. | `feed()`, `fuel()`, `smelt(10)`, `take_output()` | 10 Iron Bars | 3 |
| G12 | **Crystal Run** | Smelt 6 Crystal Iron Ore into Iron Bars. | `feed("Crystal Iron Ore", 6)`, `smelt(6)`, `take_output()` | 6 Iron Bars | 4 |

## Hybrid factory — 6 missions

These are the capstones: Automatica moves/supplies/builds, Algorithmica produces the
processed materials.

| # | Mission | Objective | Key functions | Goal | Tier |
|---:|---|---|---|---:|---:|
| H1 | **Robot-Fed Workshop** | Load 4 Wood into a station with the robot, then craft and collect 16 Planks with Python. | `put_input("Wood", 4)`; `set_recipe("Planks")`, `craft(4)`, `take_output()` | 16 Planks | 3 |
| H2 | **Color Courier** | Load 8 Cactus into a station with the robot, then craft and collect 8 orange blocks with Python. | `put_input("Cactus", 8)`; `craft_color(255, 64, 0, 8)`, `take_output()` | 8 blocks | 3 |
| H3 | **Torchline** | Craft 12 Torches with Python, then place all 12 in a line with the robot. | `set_recipe("Torch")`, `craft(3)`, `take_output()`; `build_line()` | 12 Torches placed | 4 |
| H4 | **Plank Pavement** | Craft 16 Planks with Python, then place a filled 4×4 plank floor with the robot. | `craft(4)`, `take_output()`; `build_rect(0, 0, 4, 4, true)` | 16 Planks placed | 4 |
| H5 | **Wood to Workshop** | Run one `auto_work()` cycle, withdraw 2 Wood from the chest, load it into a station, and craft 8 Planks with Python. | `auto_work()`, `withdraw("Wood", 2)`, `put_input("Wood", 2)`; `craft(2)`, `take_output()` | 8 Planks | 4 |
| H6 | **Factory Floor** | Build a 20-block stone frame with the robot, craft 8 Torches with Python, then place the torches around the frame. | `build_rect(0, 0, 6, 6, false)`; `craft(2)`, `take_output()`; `build_line()` | 1 finished floor + 8 torches | 4 |

## Why these missions work

- Every mission uses at least one custom Automatica or Algorithmica function; nothing is a
  reskinned fetch/kill quest.
- Early missions teach one call and one visible result. Later missions combine loops,
  batching, geometry, tool requirements, and multi-step factory work.
- H1–H2 use the crafting station's **input slot** as the bridge between the two systems.
- H3/H4/H6 require a manual handoff of crafted blocks into the robot's build slots; that is
  intentional, because the mission is about planning a production chain, not just running
  one script.
- Utility calls such as `list_items`, `deposit_chest`, `return_to_spawn`,
  `drop_item`, `place_at`, and the read-only `held_item` / `station_*` variables are not
  mission gates; they remain available as tools for solving the missions above.
- No new items, currencies, UI screens, or mission categories are required.

## Tracking requirements for a later implementation

These are proposal notes, not code changes:

- Add an `automatica_action(action, amount, meta)` signal from the robot bridge for
  rename, chop, deposit, withdraw, chest-read, build, mine, and combat-kill events.
- Tag build actions with the source helper (`build_line`, `build_rect`, `build_ring`,
  `build_wave`, `build_spiral`, `build_stairs`) and count **unique placed cells**.
- Add an `algorithmica_action(action, item, amount, meta)` signal from the station/furnace
  hosts for craft, craft-color, smelt, and read calls.
- For "one program" goals, reset a per-run context when the editor starts and commit the
  counters only after a successful run.
- Store unique RGB triples per program for Color Wheel and Palette Stockpile.
- For hybrid missions, record events per world and station, then require the sequence
  components within one session. Manual item handoffs can be inferred when the robot
  places the crafted block type.
- Keep the existing side-mission unlock gate and three-active-mission tracker. Order the
  new definitions by tier so Tier 1 tasks appear first.

## Save compatibility

The 20 current side-mission IDs should not simply be deleted from existing saves: side
missions award stars, and orphaned completion rows can change a player's star total.
Before implementation, either:

1. keep the old IDs in a hidden `retired` set so earned stars remain counted, or
2. migrate old side-mission completions to a grace reward / equivalent new mission.

The 30 new missions can then use fresh IDs (`side_auto_*`, `side_algo_*`,
`side_factory_*`) without colliding with legacy progress.
