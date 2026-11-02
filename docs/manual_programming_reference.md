# SandEE Programming Reference

**Game:** SandEE  
**Scope:** Automatica (Lua) and Algorithmica (Python subset)  
**Scope:** SandEE's Automatica Lua environment and Algorithmica Python-subset environment.

## 1. Summary

| Environment | Language | Host | Unique callable functions | Read-only variables | In-game reference count |
| --- | --- | --- | ---: | ---: | ---: |
| Automatica | Lua | LuaState (Rust/mlua) | 30 | 4 | 34 |
| Algorithmica — Crafting Station | Python subset | StationPythonHost → PythonState → GDScript | 7 | 0 | 7 |
| Algorithmica — Furnace | Python subset | FurnacePythonHost → PythonState → GDScript | 10 names (includes shared `take_output`) | 0 | 7 entries |
| **Algorithmica total** | Python subset | — | **16 unique** | 0 | — |

The Automatica count of 34 entries is not 34 functions. It contains 30 functions plus four read-only variables (`held_item`, `station_recipe`, `station_output_item`, `station_output_count`), and `place_item` appears in two sections. The 30 function count is the union of 15 robot functions, 10 building/chest helpers and 5 station helpers.

The Algorithmica furnace table has seven entries, but `input_name() / input_count()`, `fuel_name() / fuel_count()` and `output_name() / output_count()` contain two callable names each. The furnace therefore exposes ten names. `take_output` is also a station function, so the unique Python total is 16.

---

# Part I — Automatica (Lua)

## 2. What Automatica Is

Automatica is a programmable Lua robot placed from a Lua item. It can move, chop trees, mine, build, fight, deposit items and operate a nearby crafting station. The station is its home point. Clicking the station (or a combat robot) opens the editor.

The editor has **CODE**, **INVENTORY** and **ENCYCLOPEDIA** tabs, six templates, a code editor, **RUN**, **STOP**, **CLEAR**, **COMBAT**, **RENAME**, **CLOSE** and an output console. The code is stored on the station as `program_code` and restored on reopen.

## 3. Execution Model

- The runtime is a Lua state implemented by the Rust GDExtension (`extension/src/runner/lua.rs`).
- The editor prepends a helper library (the preamble) to every program.
- Player code runs synchronously on the main thread.
- A pre-run guard rejects obvious non-terminating loops before entering Lua.
- Long jobs (chopping, walking, building, mining) are dispatched as queued signals and continue over later physics frames.
- The editor suspends its own UI pause while a job is being dispatched and re-pauses when the chunk finishes with no job left.
- **STOP** calls the robot's stop routine and clears velocity.
- **CLEAR** empties the editor; it does not delete the saved program until a new program is run.
- A combat Automatica cannot run code until **EXIT COMBAT**.

## 4. Standard Lua Features

SandEE supports the following standard Lua features:

| Feature | Status | Notes |
| --- | --- | --- |
| Local/global variables, literals | Supported | `lua_language_features.png` |
| Tables | Supported | `local nums = {1, 2, 3}` |
| `ipairs`, `pairs`, generic and numeric `for` | Supported | `ipairs(nums)` produced `sum=6` |
| `while`, `repeat`, `if/elseif/else` | Supported | Standard Lua; safety guard applies to non-terminating forms |
| User functions, recursion, closures | Supported | `local function double(x) return x * 2 end` produced `double=8` |
| `string` library | Supported | `string.upper("sandee")` produced `SANDEE` |
| `math` library | Supported | `math.floor(3.9)` produced `3` |
| Concatenation, arithmetic, comparison, boolean | Supported | Standard Lua |
| `print` | Displayed in the editor | Output appears in the console |

The editor's lint may warn that standard names such as `ipairs`, `string.upper` and user function names are "unknown functions". Those names are not part of the SandEE API but they are valid standard Lua and execute correctly.

## 5. Automatica Function Reference

### 5.1 Robot Functions (15)

| # | Function | Syntax | Parameters | Returns | Description | Example |
| ---: | --- | --- | --- | --- | --- | --- |
| 1 | `auto_work` | `auto_work()` | None | nil | Chop trees in radius, deposit into nearest chest, return home. | `auto_work()` |
| 2 | `chop_trees` | `chop_trees(radius)` | `radius` 1–64; default 20 | nil | Chop all trees within radius, collect drops and return. | `chop_trees(12)` |
| 3 | `deposit_chest` | `deposit_chest()` | None | nil | Walk to nearest chest, deposit inventory, return. | `deposit_chest()` |
| 4 | `chest_contents` | `chest_contents()` | None | nil; prints | Print item names and quantities in nearest chest. | `chest_contents()` |
| 5 | `return_to_spawn` | `return_to_spawn()` | None | nil | Walk directly back to the station and stop. | `return_to_spawn()` |
| 6 | `craft_example` | `craft_example()` | None | nil | Select Planks, craft one, collect output. | `craft_example()` |
| 7 | `move` | `move(x, y)` | `x`, `y` pixels/second | nil | Set movement velocity. `move(0,0)` stops. Last call wins. | `move(90, 0)` |
| 8 | `interact` | `interact()` | None | nil | Execute the pending action; default is chop trees then return. | `interact()` |
| 9 | `attack` | `attack()` | None | nil | Swing the held weapon. Requires a tool. | `attack()` |
| 10 | `drop_item` | `drop_item(qty)` | `qty` max count | nil | Drop from selected build slot or general inventory. | `drop_item(3)` |
| 11 | `place_item` | `place_item(dx = 0, dy = 0)` | Tile offsets | nil | Place one block from the selected build slot. | `place_item(1, 0)` |
| 12 | `mine` | `mine(name)` | Lowercase snake_case block reference | nil | Mine matching blocks in the work radius. Requires a tool. | `mine("stone")` |
| 13 | `rename` | `rename(name)` | String | nil | Change the robot's displayed name. | `rename("Builder")` |
| 14 | `combat_mode` | `combat_mode(on)` | Boolean | nil | Enter/leave combat mode. | `combat_mode(true)` |
| 15 | `list_items` | `list_items()` | None | Table of names | Sorted list of every item name. | `for _, n in ipairs(list_items()) do print(n) end` |

### 5.2 Building, Chest and Geometry Helpers (10 unique)

| # | Function | Syntax | Parameters | Returns | Description | Example |
| ---: | --- | --- | --- | --- | --- | --- |
| 16 | `select_block` | `select_block(i)` | 0, 1 or 2 | nil | Choose the build slot used by `place_item`. | `select_block(0)` |
| 17 | `place_at` | `place_at(x, y)` | Absolute tile coordinates | nil | Place one block from the selected slot at an absolute tile. | `place_at(12, 8)` |
| 18 | `withdraw` | `withdraw("name", n)` | Name/id and max count | nil | Walk to nearest chest and take up to `n`. | `withdraw("Wood", 10)` |
| 19 | `build_line` | `build_line(x0, y0, x1, y1)` | Start/end offsets | nil | Gap-free line using Bresenham. | `build_line(1, 1, 5, 1)` |
| 20 | `build_rect` | `build_rect(x0, y0, w, h, filled)` | Offset, size, filled flag | nil | Rectangle; filled slab or border. | `build_rect(0, 0, 4, 3, false)` |
| 21 | `build_circle` | `build_circle(r, filled)` | Radius, filled flag | nil | Circle centred on the robot. | `build_circle(3, false)` |
| 22 | `build_ring` | `build_ring(r)` | Radius | nil | Hollow ring. | `build_ring(4)` |
| 23 | `build_spiral` | `build_spiral(r, turns)` | Radius, turns | nil | Archimedean spiral. | `build_spiral(4, 2)` |
| 24 | `build_wave` | `build_wave(len, amp)` | Length, amplitude | nil | Sine-wave fence. | `build_wave(6, 1)` |
| 25 | `build_stairs` | `build_stairs(n)` | Steps | nil | Diagonal staircase. | `build_stairs(4)` |

### 5.3 Station Helpers (5 functions) and Variables (4)

| # | Name | Syntax | Parameters | Returns | Description | Example |
| ---: | --- | --- | --- | --- | --- | --- |
| 26 | `craft` | `craft(n)` | Number of crafts | nil | Craft `n` of the selected automation recipe. | `craft(2)` |
| 27 | `set_recipe` | `set_recipe(name)` | Output name | nil | Select the automation recipe. | `set_recipe("Planks")` |
| 28 | `take_output` | `take_output()` | None | nil | Move finished output into the robot's stores. | `take_output()` |
| 29 | `put_input` | `put_input("name", n)` | Name, quantity | nil | Load `n` of the item into the nearest station input. | `put_input("Wood", 10)` |
| 30 | `input_slot` | `input_slot(n)` | Quantity | nil | Load `n` of the selected build-slot item into the station input. | `input_slot(5)` |
| V1 | `held_item` | `held_item` | — | Table or nil | Read-only `{name, quantity}` of the held item. | `print(held_item.name)` |
| V2 | `station_recipe` | `station_recipe` | — | String | Read-only selected recipe name. | `print(station_recipe)` |
| V3 | `station_output_item` | `station_output_item` | — | String | Read-only pending output name. | `print(station_output_item)` |
| V4 | `station_output_count` | `station_output_count` | — | Number | Read-only pending output quantity. | `print(station_output_count)` |

## 6. Complete Examples

### 6.1 Build a line

```lua
print("Building a line")
select_block(0)
build_line(1, 1, 5, 1)
print("Done")
```

The robot must have blocks in build slot 0. The editor output shows each `print`; the world shows a five-block line. This is the program used for Figures 17.2 and 17.3.

### 6.2 Chop and deposit

```lua
chop_trees(12)
deposit_chest()
return_to_spawn()
```

`chop_trees` is a long job. The editor reports that the chunk finished while the job continues; **STOP** remains enabled until the job ends. If no chest is found, `deposit_chest` reports the failure and returns.

### 6.3 Craft at a station

```lua
put_input("Wood", 10)
set_recipe("Planks")
craft(2)
take_output()
print(station_output_item, station_output_count)
```

The station must be nearby and must have the recipe's ingredients in its input slot or the player's inventory. `take_output` moves the result to the robot, not directly to the player.

### 6.4 Mine a named block

```lua
mine("stone")
```

`mine` matches normalized block references: lowercase snake_case. `mine("stone")` matches Stone, `mine("stone_block")` also matches, and `mine("birch_wood")` matches Birch Wood. The robot needs a tool and must be able to path to the target.

## 7. Lua Restrictions and Errors

| Condition | Result |
| --- | --- |
| `attack()` or `mine()` without a tool | Prints `No tool equipped`; no action. |
| `chop_trees` radius outside 1–64 | Clamped; omitted defaults to 20. |
| Build slot empty or target blocked | Placement fails with a message such as `Cannot place there — the tile is blocked.` |
| No reachable chest for `withdraw`/`deposit_chest` | Prints a failure message; robot returns. |
| No nearby crafting station | Station helper fails; output unchanged. |
| Combat mode active | Code execution refused until **EXIT COMBAT**. |
| `while true do end` or huge loop | Pre-run guard rejects before Lua executes. |
| Syntax error | Red source-located error in the output console. |
| Long job after chunk finish | Job continues; **STOP** remains available. |

---

# Part II — Algorithmica (Python Subset)

## 8. What Algorithmica Is

Algorithmica is the programming interface attached to a Crafting Station and a Furnace. It is opened from **ALGORITHMICA** in the station or furnace menu. The editor has **CODE** and **ENCYCLOPEDIA** tabs, templates, **RUN**, **CLEAR**, **RECIPES** (station) and **CLOSE**. The program is stored on the machine and survives reopening.

## 9. Runtime Model

Algorithmica does **not** embed CPython. It transpiles a Python subset into GDScript and runs the generated GDScript through `PythonState`. The transpiler is written in Rust under `extension/src/transpiler/`. This gives Python-like syntax for automation but not the Python standard library.

## 10. Language Support Matrix

The following table summarises the Python syntax accepted by Algorithmica.

| Construct | Status | Notes |
| --- | --- | --- |
| Variables, assignment, `+=` | Supported | `total = 0`, `total += n` |
| Integers, floats, strings, booleans | Supported | Literals and `True`/`False` |
| Lists, dictionaries, indexing | Supported | `names[0]`, `d["a"]`, `.get()` |
| `for` over `range` and lists | Supported | `for n in range(1, 4)`, `for n in [1,2,3]` |
| Nested loops | Supported | All pairs printed |
| Truthy `if`, `if True` | Supported | `if total:` executed |
| `while` with truthy condition | Supported | `while x:` executed; safety guard applies |
| Comparison operators (`<`, `>`, `==`) | **Not supported** | Parse error |
| `else`, `elif` | **Not supported** | Parse error |
| `def` | **Not supported** | Parse error |
| `import` | **Not supported** | Unresolved name error |
| f-strings, list comprehensions | **Not supported** | Parse error |
| `len`, `int`, `float`, `abs`, `min`, `max` | Supported | Expected values |
| `str`, `round`, `sum` | **Not supported** | Not available as functions |
| String method on a literal (`"abc".upper()`) | Supported | `ABC` |
| String method on an indexed list element | Not supported | Unresolved `Any` type |
| `print` with multiple arguments | Supported | Space-separated output |

**Practical consequence:** comparisons and `else` are unavailable. Write linear recipe scripts, loops over known ranges and simple state reads. The in-game templates follow this style.

## 11. Safety

- A pre-run guard rejects obvious non-terminating loops, including `while True:` and huge `range` bounds.
- A rejected program never reaches the machine.
- A syntax error reports `Error: Parse error` and leaves machine state unchanged.
- A successful run reports `Finished running`.
- The station host rejects furnace functions; the furnace host rejects station functions.

## 12. Crafting Station Function Reference

| # | Function | Syntax | Parameters | Returns | Description | Example |
| ---: | --- | --- | --- | --- | --- | --- |
| 1 | `craft` | `craft(amount)` | Integer amount | Crafted count (0 on failure) | Craft the selected recipe, drawing from station input first, then player inventory. | `craft(2)` |
| 2 | `craft_color` | `craft_color(r, g, b, amount)` | RGB 0–255; amount 1–32 | Crafted count | Create solid-colour blocks, one cactus per block. Pure black/white rejected. | `craft_color(255, 0, 0, 2)` |
| 3 | `get_recipe` | `get_recipe()` | None | String | Current recipe name. | `print(get_recipe())` |
| 4 | `set_recipe` | `set_recipe(name)` | Output name | Boolean | Select recipe. | `set_recipe("Planks")` |
| 5 | `output_item` | `output_item()` | None | String | Pending output item name. | `print(output_item())` |
| 6 | `output_count` | `output_count()` | None | Integer | Pending output quantity. | `print(output_count())` |
| 7 | `take_output` | `take_output()` | None | Taken count | Move output to player inventory. | `take_output()` |

### 12.1 Station example

```python
set_recipe("Planks")
craft(2)
print(output_item(), output_count())
take_output()
print("Collected the output.")
```

Example output: `Planks 8`, `Collected the output.`, `Finished running`. Two crafts of Planks yield eight because the recipe yields four per craft.

## 13. Furnace Function Reference

| # | Function | Syntax | Parameters | Returns | Description | Example |
| ---: | --- | --- | --- | --- | --- | --- |
| 1 | `feed` | `feed(name, n)` | Item name, max count | Loaded count | Move smeltable item from inventory to input. | `feed("iron_ore", 5)` |
| 2 | `fuel` | `fuel(name, n)` | Fuel name, max count | Loaded count | Move fuel from inventory to fuel slot. | `fuel("charcoal", 3)` |
| 3 | `smelt` | `smelt(n)` | Max count | Smelted count | Smelt up to `n`, consuming one input and one fuel each. | `smelt(2)` |
| 4 | `take_output` | `take_output()` | None | Taken count | Move output to player inventory. | `take_output()` |
| 5 | `input_name` | `input_name()` | None | String | Input item name or `""`. | `print(input_name())` |
| 6 | `input_count` | `input_count()` | None | Integer | Input quantity. | `print(input_count())` |
| 7 | `fuel_name` | `fuel_name()` | None | String | Fuel item name or `""`. | `print(fuel_name())` |
| 8 | `fuel_count` | `fuel_count()` | None | Integer | Fuel quantity. | `print(fuel_count())` |
| 9 | `output_name` | `output_name()` | None | String | Output item name or `""`. | `print(output_name())` |
| 10 | `output_count` | `output_count()` | None | Integer | Output quantity. | `print(output_count())` |

### 13.1 Furnace example

```python
feed("iron_ore", 2)
fuel("charcoal", 2)
smelt(2)
take_output()
print(output_name(), output_count())
```

The program completes with `Finished running`. The output read after collection was zero because the output had already been taken. For a visible result, inspect the furnace output slot or print before `take_output()`.

## 14. Algorithmica Restrictions and Errors

| Condition | Result |
| --- | --- |
| Unknown item in `feed`/`fuel` | `[feed] unknown item "..."` or `[fuel] unknown item "..."`; returns 0. |
| Non-fuel item in `fuel` | `[fuel] "..." is not a fuel`; returns 0. |
| Missing input/fuel/output space | `smelt` returns 0 or a smaller count. |
| Missing cactus | `craft_color` prints an insufficient-cactus reason and returns 0. |
| `craft_color` amount outside 1–32 | Clamped/rejected by the station. |
| Station program calls furnace function | Rejected before execution with a machine-scope message. |
| Furnace program calls station function | Rejected before execution. |
| Unsupported Python construct | `Error: Parse error` or an unresolved-name error. |
| Infinite loop pattern | Pre-run safety rejection. |

## 15. Figures

| Figure | Content |
| --- | --- |
| 17.1 | Lua editor with a build program. |
| 17.2 | Successful Lua execution output. |
| 17.3 | Five-block wood line built by Lua. |
| 17.4 | Lua syntax error. |
| 17.5 | Standard Lua features executed. |
| 17.6 | In-game Automatica encyclopedia (34 entries). |
| 18.1 | Algorithmica station editor. |
| 18.2 | Python language features executed. |
| 18.3 | Unsupported comparison parse error. |
| 18.4 | Station program producing Planks. |
| 18.5 | Station syntax error. |
| 18.6 | Furnace editor. |
| 18.7 | Furnace execution result. |
