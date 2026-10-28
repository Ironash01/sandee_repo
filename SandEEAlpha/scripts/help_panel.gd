extends PanelContainer

# ── Help & Documentation ────────────────────────────────────────────
# The pause menu's complete player reference. Content is deliberately split
# into short, scrollable categories so it fits every supported screen size,
# including cutout/notched Android displays. The panel uses the same dark
# navy styling and automatic UI scaling as Settings and the main menu.
#
# This is player-facing documentation, not debug help: it documents the real
# controls, systems, progression and limitations of the shipped game.

signal close_requested

const C_PANEL     := Color(0.08, 0.10, 0.20, 0.97)
const C_BORDER    := Color(0.22, 0.32, 0.58, 1.00)
const C_TITLE     := Color(0.80, 0.90, 1.00, 1.00)
const C_MUTED     := Color(0.55, 0.65, 0.85, 1.00)
const C_ACCENT    := Color(0.55, 0.86, 0.98, 1.00)
const C_HEADING   := Color(0.88, 0.95, 1.00, 1.00)
const C_WARN      := Color(1.00, 0.78, 0.45, 1.00)
const C_GOOD      := Color(0.62, 0.95, 0.70, 1.00)

const CATEGORIES: Array = [
	{
		"id": "start",
		"title": "Start Here",
		"body": """[b][color=#8fd8ff]WELCOME TO SANDEE[/color][/b]
SandEE is a 2D sandbox about gathering, building, survival, automation and learning to program. Your world is generated from a seed and saves its terrain changes, containers, missions, dungeon progress and Bestiary records.

[b]Your first session[/b]
• You begin in a guided camp. Each lesson shows one short action, an arrow and a highlight on the exact target.
• Your starter kit contains the Wooden Axe, Wooden Pickaxe, Wooden Sword and exactly 10 Bread. It is granted once per new world.
• Follow the objective card: move twice, select the axe, chop a tree, pick up the Wood and craft the Crafting Station. The first dungeon lesson begins right after: follow the marker to the nearest entrance and confirm it.
• The dungeon teaches the Knowledge Altar and route markers, then the Quiz Altar. Afterwards the camp teaches Automatica, Algorithmica, regular caves, Pixie Caves and Skyglass Waypoints. The first Pixie Cave is a safe introduction with no pixies; later Pixie Caves are guarded.
• Skipping is safe. It never removes items, features or later content.
• After onboarding, a settings tour opens Settings and highlights each control (no arrow) with a short explanation; use NEXT/SKIP to move through it.
• Open your inventory early (E on desktop, INV on Android). The hotbar stays visible while the inventory is open.
• Follow the objective card at the top-centre of the screen during onboarding. Tutorial targets have a pulsing marker and a compass arrow above the player.

[b]HUD at a glance[/b]
• Top-right: PAUSE button.
• Bottom-centre: health, stamina and the 9-slot hotbar (8 item slots + INV on Android).
• Right side: stars and the mission tracker.
• Bottom-left: minimap. Click it or press M to open the full map.
• Left-middle: active Automatica status.
• Top-centre: short notifications for pickups, fishing, deaths and discoveries.

[b]Long-term goals[/b]
• Progress the Python and Lua dungeon tracks. Each language teaches its own programming entries.
• Defeat the Hitman miniboss to complete the main story.
• Complete the main tracks, the Hitman finale and any extra dungeons to unlock the 20 side missions.
• Fill the Bestiary by sighting and defeating every creature.
• Build, farm, fish, smelt, automate and decorate as much as you like. The world does not end after the credits-like milestones.""",
	},
	{
		"id": "controls",
		"title": "Controls",
		"body": """[b][color=#8fd8ff]DESKTOP[/color][/b]
• [b]WASD / arrow keys[/b] — move.
• [b]Shift[/b] — sprint while moving. Sprint drains stamina; it stops at zero and needs 15 stamina before it can restart.
• [b]Left mouse[/b] — swing the held item, use a tool, attack, mine, interact, or place a block in build mode. Hold it for repeated swings.
• [b]Mouse aim[/b] — swings and sword grass cuts follow the pointer; if the pointer is on the player, the last movement direction is used.
• [b]E[/b] — open/close the inventory.
• [b]1–9[/b] or the [b]mouse wheel[/b] — select a hotbar slot.
• [b]Ctrl[/b] — toggle build mode.
• [b]M[/b] — open/close the full map.
• [b]Esc[/b] — pause, close the innermost panel, or cancel a tap-to-move order.
• [b]Enter / Space[/b] — advance dialogue.
• [b]Shift + click[/b] — mine/destroy a placed block, chest, station or furnace instead of using it.
• [b]F1[/b] — show/hide the bottom on-screen control hints (on by default). Their keycaps light up while pressed.
• The LMB hint follows the hovered target (use/mine/attack, move/interact/chase); [b]Shift + LMB[/b] becomes DESTROY on removable targets.

[b]Point-and-click (optional)[/b]
Enable [b]Settings → Controls → Point-and-Click Movement[/b]. Clicking the ground walks there; clicking an interactable walks to one-block range and opens/interacts without swinging your held item; clicking a hostile creature chases and attacks it. Moving with WASD cancels the order. [b]Automatic Sprint[/b] uses stamina exactly like Shift. Build mode, UI panels and right-clicks are never intercepted. On Android the movement joystick is hidden while point-and-click is enabled; joystick mode keeps it visible. On desktop, while a usable item is selected (food, Life/Stamina Crystal, fishing rod, hoe or bucket), a click uses that item instead of issuing a move/interact order.

[b][color=#8fd8ff]ANDROID / TOUCH[/color][/b]
• Left joystick — move in joystick mode. A second finger can use buttons and the hotbar while moving. The joystick is hidden in point-and-click mode.
• [b]SPRINT[/b] — hold to sprint.
• [b]BUILD[/b] — toggle build mode (BUILD ON while active).
• [b]INTERACT[/b] — context action for a nearby chest, crafting station or furnace. Its label changes to OPEN / CRAFT / SMELT.
• [b]INV[/b] — the last hotbar slot is reserved for the inventory on Android. Android therefore has 8 item slots instead of 9.
• Tap the world to move, mine, attack, fish or place a block. Tap yourself with food selected to eat it.
• Android Back closes the current panel or menu.
• [b]DONE[/b] appears above the on-screen keyboard and dismisses it.
• The custom cursor is desktop-only; touch uses the emulated pointer and standard UI feedback.""",
	},
	{
		"id": "survival",
		"title": "Survival & World",
		"body": """[b][color=#8fd8ff]HEALTH & STAMINA[/color][/b]
• Maximum health is 100. Maximum stamina is 50.
• Sprinting drains about 10 stamina per second; standing or walking restores about 5 per second.
• There is no hunger or thirst meter. Food is a healing item: select it in the hotbar and click/tap to eat (the click must not be aimed at a solid object).
• Cooked fish restore 50 health. Bread restores 20. Apples and raw meat restore smaller amounts. You cannot eat at full health.

[b]Death & respawn[/b]
• Dying starts a 5-second respawn countdown.
• You respawn in the overworld at the active Bonfire, or at the world spawn if no Bonfire is active.
• Death does not delete your inventory. Build mode and pending actions are cancelled.
• You always return to the overworld even if you died in a cave or dungeon.

[b]World & weather[/b]
• A full day/night cycle lasts 24 real minutes: 12 minutes of day, 12 minutes of night. The game starts at noon.
• Night raises the hostile population cap and spawn rate. Some creatures only appear at night.
• Creatures that naturally spawn during the day take 40% less damage from every hit.
• Biomes include plains/forest, desert and snowy land, plus water, caves, pixie caves and the overworld ocean-edge.
• Entering the desert spawns a group of Desert Worms.
• Snow biomes can trigger a snowstorm: heavy particles, reduced visibility and movement at 55% speed. Storms end when you leave the snow or when night falls.
• Snowfall and biome ambience are visual; they do not damage you by themselves.
• Sunshard Finches fly overhead in daytime flocks; Dusk Kites replace them at night. Both are harmless ambience.

[b]Shelter & safe rooms[/b]
• A valid house is a sealed room with a door and at least a 3×3 interior. Ambient hostile spawns are suppressed inside it.
• Dungeon Knowledge altar rooms contain green safe-zone markers. Stepping on one makes you invulnerable, heals 1 health per second, and disintegrates hostiles inside the room. Quiz rooms are combat rooms and are not safe zones.
• A dungeon safe zone lasts 30 seconds and then needs 20 seconds to re-arm. Leaving the room ends it early.
• Safe-zone kills grant no loot or Bestiary credit.

[b]Tools & mining[/b]
• Blocks have a minimum pickaxe tier. The Wooden Pickaxe is tier 1 and mines stone, iron and copper; the Iron Pickaxe is tier 5; the Diamond Pickaxe is tier 10 and reaches diamond ore.
• Hold left-click on a block to break it. A break ring shows progress; progress on the same tile is remembered for a short time between clicks.
• Axes speed up wood and wooden blocks. Swords cut grass and harvest mature wheat.
• Torches light the area at night and inside caves and dungeons. A placed torch beside a wall uses the connected-wall visual.""",
	},
	{
		"id": "building",
		"title": "Building & Farming",
		"body": """[b][color=#8fd8ff]BUILD MODE[/color][/b]
• Press [b]Ctrl[/b] on desktop or [b]BUILD[/b] on Android. A translucent block ghost and a tile grid appear.
• You may place within 6 blocks of the player. Red ghost = occupied, in water, too far away, or blocked by the player.
• Place blocks, floors, doors, stations and furniture from the selected hotbar slot.
• [b]Shift + click[/b] a placed block to mine/destroy it. Chests, stations and furnaces also use Shift + click to be removed.
• Floors are walkable and render beneath the player. Walls block movement. Doors can be opened/closed with a plain click.
• Build a sealed room with a door and a 3×3 interior to make a house. Houses block ambient hostile spawns and darken the world outside while you are indoors. The mission tracker's "Build a shelter" objective uses the same rule.
• Build mode is disabled inside dungeons, and you cannot place on dungeon/portal footprints or unopened cave entrances.

[b]Containers & stations[/b]
• Chests hold 8 stacks and open in the inventory panel. Rare dungeon chests contain automation materials and food.
• Crafting Station, Furnace and Color Crafter are placeable machines. Plain-click one to open it; Shift-click to mine it. Their state is saved, including station/furnace programs and container contents.
• Bonfires are placeable respawn points. Plain-click a Bonfire to set it active, click again to clear it. Only one Bonfire can be active at a time, and only in the overworld. Breaking the active Bonfire resets respawn to world spawn.
• Torches and bonfires are visual light sources. The game does not simulate a torch fuel timer.

[b][color=#8fd8ff]FARMING[/color][/b]
1. Cut grass with a sword. Each cut has a 25% chance to drop Wheat Seeds.
2. Select the Iron Hoe and click a grass tuft to till it into Tilled Ground. The plot must be within 20 blocks of water.
3. Select Wheat Seeds in build mode and click the tilled plot to plant.
4. Wheat ripens in 3 real minutes. Cut the mature crop with a sword to harvest 1–3 Wheat and a 50% chance of a seed.
5. Three Wheat make one Bread: use the inventory's CRAFT tab (hand recipe) or a Crafting Station.

[b]Water & buckets[/b]
• An empty Bucket clicked on water becomes a Water Bucket. A Water Bucket clicked on ground pours a water source.
• Water blocks movement but can be bridged with blocks. Water is required for tilled plots and can be moved to make a farm anywhere.

[b][color=#8fd8ff]FISHING[/color][/b]
• Select the Fishing Rod and click/tap water within 8 blocks.
• The cast takes 5 seconds and has a 70–90% catch chance. Moving more than about two tiles, unequipping the rod, or leaving the scene cancels it.
• Catches are Charlie, Allan, Glep and Pim. Cook them in a Furnace to restore 50 health each.

[b]Cactus[/b]
• Cacti grow in the desert over time. Harvest them for Cactus, used by the Color Crafter and as high-level furnace fuel.""",
	},
	{
		"id": "crafting",
		"title": "Crafting & Machines",
		"body": """[b][color=#8fd8ff]INVENTORY TABS[/color][/b]
• [b]INVENTORY[/b] — 20 player slots plus your hotbar. The hotbar stays visible and interactive while this panel is open, so stacks can be dragged both ways. When a chest is open its 8 slots appear below yours.
• [b]CRAFT[/b] — recipes that need no station: the Crafting Station, Color Crafter, Bread and other hand recipes.
• [b]ENCYCLOPEDIA[/b] — the Programming Encyclopedia. Function references are always available; language entries unlock through dungeon Knowledge Altars.
• [b]BESTIARY[/b] — creatures you have seen and studied.
• Hover an item to see its description, damage, fuel value and other properties. On touch, tap and hold for a tooltip.

[b][color=#8fd8ff]CRAFTING STATION[/color][/b]
• Place it from the hotbar, then plain-click it.
• Choose a category (Materials, Blocks, Weapons & Tools, Others), choose a recipe, check the ingredients, then press [b]CRAFT[/b]. Manual crafting delivers the result directly to your inventory.
• Station recipes include planks, doors, floors, torches, chests, tools, weapons and the Furnace.
• [b]ALGORITHMICA[/b] opens the Python automation panel for this station. It is code-only: write Python with [b]set_recipe()[/b], [b]craft()[/b], [b]craft_color()[/b] and [b]take_output()[/b], then run it. Function and item names autocomplete as you type.
• Recipe selection and item feeding are code-driven. Crafting consumes the station's input (if a robot loaded one) and then your inventory; call [b]take_output()[/b] to collect the finished items.

[b][color=#8fd8ff]FURNACE[/color][/b]
• Load a smeltable item into INPUT and a fuel item into FUEL, then press [b]SMELT[/b].
• Each smelt takes 5 seconds and consumes one input plus one fuel whose fuel level meets the recipe requirement.
• Fuels: Wood / Birch / Snowy Wood, planks, Charcoal (fuel level 2) and Cactus (fuel level 5).
• Smelts: Copper Ore → Copper, Iron Ore → Ironbar, Silicon Ore → Silicon, Diamond Ore → Diamond, every crystal ore → its base material, Wood → Charcoal, and raw fish/dog meat → cooked food.
• The furnace previews the output before you commit. It cannot smelt without fuel or without output space.
• Output can be taken from the furnace slot or via Algorithmica's take_output().

[b][color=#8fd8ff]COLOR CRAFTER[/color][/b]
• Craft the machine with 20 Cactus + 10 Ironbar (hand recipe), place it, and plain-click it.
• Pick a colour with the wheel, RGB sliders or numeric R/G/B fields, then craft. Each block costs 1 Cactus.
• Pure black and pure white are rejected. The result is a placeable solid-colour block that saves with its RGB value.
• Algorithmica can do the same from a crafting station with craft_color(r, g, b, amount) for 1–32 blocks.
• Color blocks are normal building blocks and can be mined/placed like other blocks.""",
	},
	{
		"id": "programming",
		"title": "Programming & Automation",
		"body": """[b][color=#8fd8ff]TWO LANGUAGES, TWO MACHINES[/color][/b]
• [b]Lua → Automatica[/b]: the robot companion. Automatica mines, chops, farms, builds, deposits loot, works stations and can become a combat follower.
• [b]Python → Algorithmica[/b]: the automation panel inside Crafting Stations and Furnaces. It crafts items, colours blocks, loads fuel and smelts.
• The Programming Encyclopedia (inventory tab) lists every function. Function lists are always visible; language concepts unlock as dungeon Knowledge Altars are read.
• After your first dungeon, guided camp lessons walk through Automatica's build-line and combat examples, then Algorithmica's print example. Exploration lessons unlock only after the runs succeed.

[b][color=#8fd8ff]AUTOMATICA (LUA)[/color][/b]
1. Craft/obtain an Automatica item, select it, and place it like a block.
2. Plain-click the station to open its console. The editor has code, RUN/STOP, output, inventory, a tool slot and three build slots.
3. Write Lua and press RUN. The robot executes the script against the real world; progress and messages appear in the output panel.
4. Right-click the station to toggle its blue work-radius ring. The default radius is 20 blocks (1–64 supported by radius calls).
5. Drag items into its inventory/build slots, or use withdraw("name", n) to pull from a nearby chest. The tool slot is required for mine() and attack().
6. Common calls: auto_work(), chop_trees(radius), deposit_chest(), return_to_spawn(), mine("Stone", radius), place_item(), build_line(), build_rect(), build_circle(), set_recipe(), craft(n), put_input(), take_output().
7. [b]combat_mode(true)[/b] turns the robot into a permanent combat follower. It gains 250 HP, follows through caves/dungeons, and attacks with its tool. Combat mode cannot run code. A combat Automatica can be permanently terminated from [b]Pause → Automatica Management[/b].
8. You can place up to 31 Automatica stations per world. Each has independent code, inventory and build slots.

[b][color=#8fd8ff]ALGORITHMICA (PYTHON)[/color][/b]
• Open a Crafting Station or Furnace and press its [b]ALGORITHMICA[/b] button.
• Crafting Station calls: set_recipe("Planks"), craft(n), get_recipe(), output_item(), output_count(), take_output(), craft_color(r, g, b, n).
• Furnace calls: feed("Iron Ore", n), fuel("Charcoal", n), smelt(n), take_output(), input_name()/input_count(), fuel_name()/fuel_count(), output_name()/output_count().
• Programs run against the machine's real slots. Load input/fuel first (or use feed/fuel); smelt consumes one fuel per item. Output stays in the machine until take_output().
• Use the [b]TEMPLATE[/b] button to load a complete station or furnace example, then change the recipe, item ids and amounts.
• The guided Algorithmica lesson opens the furnace with ready-to-run print("Algorithmica ready") code — just press RUN.
• The editor prevents adding new Python functions, but recipe discovery is built in: use the RECIPES button to print every recipe and its scripting item ids.
• Python and Lua are separate interpreters. A station's Python code is not run by Automatica, and Automatica cannot run a station's Python panel.

[b]Practical tips[/b]
• Start with the editor's build-line example or the Algorithmica TEMPLATE button, then use get_recipe/list_items output to learn exact item ids.
• A robot's work radius is measured from its station, not its current position.
• Chests are the robot's delivery network: deposit_chest() fills the nearest chest with space.
• The Programming Encyclopedia's function descriptions are the authoritative in-game API reference.""",
	},
	{
		"id": "dungeons",
		"title": "Dungeons & Bestiary",
		"body": """[b][color=#8fd8ff]DUNGEON PROGRESSION[/color][/b]
• The overworld always holds the current entrance for each active language track: one Lua and one Python dungeon during the main phase.
• Walk onto an entrance and confirm Enter, or click its door. A temporary one-way waypoint appears near the player or camp; step on it to travel to the current dungeon entrance. It is consumed on use and is saved.
• The mission tracker shows the current Lua and Python dungeon rows, then the Hitman finale (and any active extra dungeon).
• Clearing a dungeon removes its overworld entrance, awards its mission star and spawns the next mission in that language's track.
• After both main language tracks, the shared [b]Hitman Miniboss[/b] dungeon unlocks. Defeating it completes the main story; clearing it together with the main tracks and any extra dungeons unlocks the 20 side missions. Side missions have their own tracker section and use the same star/progress system.

[b]Inside a dungeon[/b]
• Dungeons are combat gauntlets with traps, flame vents, hostile spawns and treasure chests.
• The first safe room contains a [b]Knowledge Altar[/b]. Read and close its entry to learn a programming concept permanently for that world. The altar also keeps a pageable archive of every entry you have learned.
• Guided first-dungeon runs show numbered floor markers along a safe route to the final Quiz Altar. The route follows real floor cells and avoids trap tiles.
• The final room contains a [b]Quiz Altar[/b]. Answer every multiple-choice or compiler question correctly to clear the dungeon. Wrong answers can be retried; compiler questions run your code and check its output. [b]HINT[/b] prepares the current answer: it fills compiler code with the expected print program or highlights the correct multiple-choice button. It becomes [b]NEXT[/b], which only dismisses the hint. You still press [b]RUN[/b] or tap the answer yourself. Each hint costs one blue star except during the first dungeon, and each wrong code run also costs one. Review the results and press [b]Done[/b] to return to the overworld.
• Green safe-zone markers in Knowledge altar rooms grant 30 seconds of invulnerability, healing and hostile disintegration. Safe-zone kills give no loot or Bestiary credit.
• The dungeon map is fog-of-war and has no legend. The overworld and cave maps do.
• Dungeon progress, cleared entrances, seeds and looted container state are saved per world.

[b][color=#8fd8ff]BESTIARY[/color][/b]
• Open [b]Inventory → BESTIARY[/b]. Creatures are added when they first enter your view.
• A sighting shows the name, portrait and category.
• Defeat the creature once to [b]study[/b] it, revealing its field notes, maximum health and complete drop table.
• Bestiary state is per world and saved. Safe-zone disintegrations do not count as kills.
• Categories include Friendly, Overworld, Lua Dungeon and Python Dungeon creatures.""",
	},
	{
		"id": "maps",
		"title": "Maps, Missions & Saving",
		"body": """[b][color=#8fd8ff]MISSIONS & STARS[/color][/b]
• The right-side mission tracker shows up to three active gameplay missions at a time. Started missions are prioritised so progress is never hidden.
• Dungeon rows start at three blue stars. Each hint (except in the first dungeon) or wrong code run costs one; the score stops at zero but never blocks completion. Other missions award a star when completed.
• Side missions unlock after the main tracks, Hitman finale and any extra dungeons are complete.
• Mission, star, side-mission and dungeon-clear progress is stored in the world save. Automatica status appears in the left HUD and is managed from Pause > Automatica Management.
• Online accounts also record cloud star totals and leaderboard entries.

[b][color=#8fd8ff]MAPS & WAYPOINTS[/color][/b]
• The bottom-left minimap follows you. Click it or press M to open the full map.
• On the full map: drag to pan, mouse wheel or +/− to zoom, X or Esc/M to close. The map fills the safe content area and hides the gameplay HUD.
• Fog of war is tracked per world; the map reveals terrain as you explore. The legend identifies you, enemies, friendly creatures, Bonfires, Automatica, dungeon entrances and Skyglass waypoints; cave maps mark their entrance/exit.
• [b]Skyglass Waypoints[/b] are tall ruined towers scattered across the overworld. Walk near one and click it to open the world waypoint map, then select another tower to teleport.
• Teleporting plays a recall/white-fade effect. You cannot teleport while another waypoint transition is running, and a safe landing spot must exist near the tower.
• Dungeon entrances and their temporary one-way return waypoints are separate from permanent Skyglass towers.

[b][color=#8fd8ff]SAVING[/color][/b]
• Each world is a save slot. The game autosaves every 60 seconds while you are alive and not in an unsafe transition.
• The game also saves when the app is backgrounded on Android and when you choose [b]Quit to Menu[/b].
• Saves are written atomically with a temporary file and a .bak safety copy. A crash during a save can leave a backup, never a half-written main save.
• World seed, terrain edits, placed blocks, containers, machines, programs, player position, missions, tutorial progress, dungeon state, Bestiary and knowledge are all saved.
• The main menu's [b]Worlds[/b] screen creates, loads, renames and deletes worlds; deletion is permanent for that device.

[b]Cloud saves[/b]
• Sign in from the startup screen or main menu. An online account is required before worlds can be created or opened. Worlds upload automatically after saves and download during the sign-in sync; each account sees only its own cloud-backed worlds.
• Two devices sharing the same world: the newer save revision wins when the world UID matches.
• A cloud save in a slot with a different world UID is treated as a conflict and needs attention in [b]Cloud Saves[/b]. Download a copy there to restore it locally.
• [b]Play Offline[/b] uses the previously verified local copies belonging to the currently signed-in account. Other accounts' worlds are never listed, and new worlds require an online session.
• If an account switch or cleanup is interrupted, world access stays blocked until the account is verified again.""",
	},
	{
		"id": "settings",
		"title": "Settings & Troubleshooting",
		"body": """[b][color=#8fd8ff]SETTINGS[/color][/b]
The pause menu and main menu share the same settings panel:
• [b]Audio[/b] — master, music and SFX volume.
• [b]Display[/b] — camera zoom (0.5×–3.0×), fullscreen (desktop) and VSync (desktop). Frame rate is fixed at 60 FPS.
• [b]Gameplay[/b] — pause while the inventory is open and an opaque quest-tracker background.
• [b]Controls[/b] — point-and-click movement, automatic sprint, and rebinding for movement, inventory and all nine hotbar slots. Click a binding, press a key, or press Esc to cancel.
• UI scale and safe-area layout are automatic. The game adapts to window size, cutouts, notches, system bars, 180° rotation and Android soft-keyboard height.

[b]Interface tips[/b]
• The inventory opens as a paused modal; closing it resumes gameplay.
• ESC/Back closes the innermost layer first: rebind prompt, settings, Automatica management, Help, then the pause menu.
• On Android the last hotbar slot is INV. If an item was parked there when Android mode was detected, it is moved into the inventory so it is not lost.
• The custom cursor is desktop-only and changes over chests, crafting stations, furnaces, Color Crafters and other interactables. It falls back to the normal arrow over UI, menus, paused gameplay and build mode.
• The top-right SKIP button shown while dialogue is active skips the current lesson without breaking the dialogue's modal state. The objective card can also offer Skip lesson after dialogue for lessons that are still running.

[b][color=#8fd8ff]COMMON PROBLEMS[/color][/b]
• [b]A machine does nothing[/b] — check that it has input, fuel/output space, and that its tool slot (Automatica mining/attacking) is filled.
• [b]Furnace will not smelt[/b] — the fuel level must meet the recipe requirement and the output slot must have room. One fuel is consumed per item.
• [b]Algorithmica reports a name error[/b] — use the RECIPES button to see exact scripting ids, and remember station programs only accept station functions.
• [b]A robot is stuck[/b] — return_to_spawn(), or pick a nearer station/clear the area. The pause menu's Automatica Management lists active robots.
• [b]A dungeon entrance disappeared[/b] — clearing a dungeon removes that entrance and spawns the next mission. The temporary return waypoint is also consumed.
• [b]Cloud world is missing[/b] — sign in, open Cloud Saves and download the copy. A different world UID in the same slot is a protected conflict, not an automatic overwrite.
• [b]I want a fresh tutorial[/b] — tutorial progress is per world. A new world starts onboarding again; an existing world keeps its completed lessons.""",
	},
]

var _content: RichTextLabel = null
var _content_scroll: ScrollContainer = null
var _category_buttons: Dictionary = {}
var _current_category: String = "start"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()

func _build() -> void:
	var s: float = Global.ui_scale
	custom_minimum_size = Global.ui_fit_min_size(Vector2(780, 500))

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = C_PANEL
	panel_style.border_color = C_BORDER
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(6)
	panel_style.content_margin_left = int(22 * s)
	panel_style.content_margin_right = int(22 * s)
	panel_style.content_margin_top = int(18 * s)
	panel_style.content_margin_bottom = int(18 * s)
	add_theme_stylebox_override("panel", panel_style)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", int(8 * s))
	add_child(outer)

	var title := Label.new()
	title.text = "HELP & DOCUMENTATION"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", Global.ui_type_size(Global.UI_TYPE_HEADING))
	title.add_theme_color_override("font_color", C_TITLE)
	outer.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Controls, systems and progression for the complete game."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.add_theme_font_size_override("font_size", Global.ui_type_size(Global.UI_TYPE_CAPTION))
	subtitle.add_theme_color_override("font_color", C_MUTED)
	outer.add_child(subtitle)

	var divider := ColorRect.new()
	divider.color = C_BORDER
	divider.custom_minimum_size = Vector2(0, maxi(1, int(1 * s)))
	outer.add_child(divider)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", int(14 * s))
	outer.add_child(body)

	var side_scroll := ScrollContainer.new()
	side_scroll.custom_minimum_size = Vector2(int(178 * s), 0)
	side_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	body.add_child(side_scroll)

	var sidebar := VBoxContainer.new()
	sidebar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sidebar.add_theme_constant_override("separation", int(4 * s))
	side_scroll.add_child(sidebar)

	var group := ButtonGroup.new()
	group.allow_unpress = false
	for entry_value in CATEGORIES:
		var entry: Dictionary = entry_value as Dictionary
		var cat_id := str(entry.get("id", ""))
		var btn := Button.new()
		btn.text = str(entry.get("title", cat_id.capitalize()))
		btn.toggle_mode = true
		btn.button_group = group
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(0, maxi(30, int(23 * s)))
		btn.add_theme_font_size_override("font_size", Global.ui_type_size(Global.UI_TYPE_CAPTION))
		btn.add_theme_color_override("font_color", C_MUTED)
		btn.add_theme_color_override("font_hover_color", C_TITLE)
		btn.add_theme_color_override("font_pressed_color", C_TITLE)
		btn.add_theme_color_override("font_hover_pressed_color", C_TITLE)
		var normal := StyleBoxFlat.new()
		normal.bg_color = Color(0, 0, 0, 0)
		normal.content_margin_left = int(9 * s)
		normal.content_margin_right = int(7 * s)
		normal.content_margin_top = int(3 * s)
		normal.content_margin_bottom = int(3 * s)
		var hover := normal.duplicate() as StyleBoxFlat
		hover.bg_color = Color(0.13, 0.19, 0.34, 0.92)
		hover.border_color = C_BORDER
		hover.set_border_width_all(1)
		hover.set_corner_radius_all(4)
		var pressed := hover.duplicate() as StyleBoxFlat
		pressed.bg_color = Color(0.14, 0.24, 0.42, 0.98)
		pressed.border_color = C_ACCENT
		pressed.border_width_left = maxi(2, int(3 * s))
		pressed.set_corner_radius_all(4)
		btn.add_theme_stylebox_override("normal", normal)
		btn.add_theme_stylebox_override("hover", hover)
		btn.add_theme_stylebox_override("pressed", pressed)
		btn.add_theme_stylebox_override("hover_pressed", pressed)
		btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		btn.pressed.connect(_show_category.bind(cat_id))
		sidebar.add_child(btn)
		_category_buttons[cat_id] = btn

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(right)

	_content_scroll = ScrollContainer.new()
	_content_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_content_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	right.add_child(_content_scroll)

	_content = RichTextLabel.new()
	_content.bbcode_enabled = true
	_content.fit_content = true
	_content.scroll_active = false
	_content.selection_enabled = false
	_content.mouse_filter = Control.MOUSE_FILTER_PASS
	_content.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_font_size_override("normal_font_size", Global.ui_font_size(12.5))
	_content.add_theme_font_size_override("bold_font_size", Global.ui_font_size(12.5))
	_content.add_theme_font_size_override("italics_font_size", Global.ui_font_size(12.5))
	_content.add_theme_font_size_override("mono_font_size", Global.ui_font_size(11.5))
	_content.add_theme_constant_override("line_separation", int(3 * s))
	_content.add_theme_color_override("default_color", C_HEADING)
	_content_scroll.add_child(_content)

	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	footer.add_theme_constant_override("separation", int(8 * s))
	outer.add_child(footer)

	var version := Label.new()
	version.text = "v%s - scroll to read" % Global.game_version()
	version.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	version.add_theme_font_size_override("font_size", Global.ui_type_size(Global.UI_TYPE_CAPTION))
	version.clip_text = true
	version.add_theme_color_override("font_color", C_MUTED)
	footer.add_child(version)

	var back := Button.new()
	back.text = "< Back"
	back.custom_minimum_size = Vector2(int(132 * s), maxi(36, int(34 * s)))
	back.add_theme_font_size_override("font_size", Global.ui_type_size(Global.UI_TYPE_LABEL))
	back.pressed.connect(func() -> void: close_requested.emit())
	footer.add_child(back)

	_show_category(_current_category)

func _show_category(cat_id: String) -> void:
	_current_category = cat_id
	var found: bool = false
	for entry_value in CATEGORIES:
		var entry: Dictionary = entry_value as Dictionary
		if str(entry.get("id", "")) != cat_id:
			continue
		found = true
		if _content != null:
			_content.text = str(entry.get("body", ""))
			_content_scroll.set_deferred("scroll_vertical", 0)
		break
	if not found and not CATEGORIES.is_empty():
		_show_category(str((CATEGORIES[0] as Dictionary).get("id", "start")))
		return
	for key in _category_buttons:
		var btn: Button = _category_buttons[key] as Button
		btn.button_pressed = key == cat_id
