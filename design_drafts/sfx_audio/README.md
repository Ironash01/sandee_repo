# SandEE SFX requirements

**Status:** analysis only. No audio assets, playback code, buses, or UI were changed.

## Key findings

- The only audio files in the repo are **13 BGM tracks** under `SandEEAlpha/bgm/`.
- No SFX files, `AudioStreamPlayer` nodes, or SFX playback calls were found.
- The settings panel already expects `Master`, `Music`, and `SFX` buses, but no audio bus layout file was found. The `SFX` slider currently has no bank to control.
- Every cue below is therefore missing. BGM is deliberately excluded from this list.

## Scope

- **90 cue families** across 7 categories.
- Raw asset estimate: **~312-393 files** if every recommended variant is authored; **~88-114 files** for a P0-only first pass.
- Variant counts are recommendations, not final asset counts. Repetitive actions should use 2-4 variants plus slight pitch randomization.
- Priority: **P0** = core loop, **P1** = important game feel, **P2** = polish/optional ambience or network feedback.

| Priority | Cue families |
|---|---:|
| P0 | 15 |
| P1 | 53 |
| P2 | 22 |

| Category | Cue families |
|---|---:|
| Player | 8 |
| Tools & World | 11 |
| Items & Interactables | 12 |
| UI & Progression | 13 |
| Crafting & Automation | 14 |
| Combat & Mobs | 19 |
| World & Dungeon | 13 |

The full cue sheet with IDs, triggers, recommended sounds, variant counts, and notes is in `sfx_inventory.csv`.

A sourced open-source 8-bit candidate list, including exact pack files for each cue, is in `open_source_8bit/`.

## Cue sheet

### Player

| ID | Action | Trigger | Sound direction | Variants | Priority |
|---|---|---|---|---:|---|
| `sfx_player_footsteps` | Footsteps by surface | Walking or sprinting on grass, dirt, stone, snow, wood, sand, or shallow water | Short material-specific step; 3-4 pitch variants per surface | 21-28 | P0 |
| `sfx_player_sprint` | Sprint start / stamina empty | Sprint begins; stamina hits exhaustion; recovery | Short exertion cue, tired breath, stamina warning | 3 | P1 |
| `sfx_player_hurt` | Player takes damage | Global.damage_player applies damage (not blocked by i-frames) | Short pain grunt + impact layer; light/heavy variants | 3 | P0 |
| `sfx_player_death` | Player death | Death sequence starts | Falling body, equipment clatter, low death sting | 1-2 | P0 |
| `sfx_player_respawn` | Player respawns | Respawn at bonfire/world spawn | Soft whoosh + settling step | 1 | P1 |
| `sfx_player_eat` | Eat food / drink | Food item consumed | Crunch/chew/sip set | 3 | P1 |
| `sfx_player_crystal` | Use Life/Stamina crystal | Stat crystal consumed | Crystalline chime + healing shimmer | 2 | P1 |
| `sfx_player_low_health` | Low-health heartbeat | Health below threshold | Muffled heartbeat/breathing loop | 1 loop | P2 |

### Tools & World

| ID | Action | Trigger | Sound direction | Variants | Priority |
|---|---|---|---|---:|---|
| `sfx_tool_swing` | Sword/tool swing | swing_held_item / swing_performed | Airy whoosh; sword, axe, and pickaxe variants | 3-4 | P0 |
| `sfx_tool_impact` | Tool hits a target | Sword hitbox hits mob, block, tree, or grass | Flesh, wood, stone, soft-earth impact layers | 12-16 | P0 |
| `sfx_block_break` | Block breaks | placeable_block._break or cave _break_tile | Wood, stone, soft earth, ore break set | 12-16 | P0 |
| `sfx_block_place` | Block placed | world.place_block_at or robot placement | Wood, stone, soft earth placement thud | 9 | P1 |
| `sfx_tree_chop_fall` | Tree chopped and falls | tree.gd takes chop damage; final chop frees the tree | Wood crack, creak, fall, ground impact | 3-4 | P1 |
| `sfx_grass_cut` | Grass cut | world._cut_grass_row / sword grass cut | Sharp swish + soft foliage rustle | 2 | P1 |
| `sfx_grass_rustle` | Walk through grass | Player moves through a grass tuft | Soft brush/rustle | 2 | P2 |
| `sfx_farming` | Till, plant, water, harvest | Hoe use, seed placement, bucket pour, crop harvest | Soil scrape, seed drop, water pour, plant pull | 6-8 | P1 |
| `sfx_build_mode` | Build mode toggle | Global.block_mode changes | Short UI/mechanical toggle | 2 | P2 |
| `sfx_placement_error` | Invalid placement | Ghost turns red / placement rejected | Dull denial buzz or click | 1-2 | P1 |
| `sfx_inventory_full` | Inventory or chest full | add_item / deposit_item fails | Low error thunk | 1 | P1 |
### Items & Interactables

| ID | Action | Trigger | Sound direction | Variants | Priority |
|---|---|---|---|---:|---|
| `sfx_item_pickup` | Item pickup | Drop enters inventory or hotbar | Short bright pickup blip; stack-size variants | 2-3 | P0 |
| `sfx_item_drop` | Item drop | Player or robot drops an item | Soft item drop/land | 1-2 | P1 |
| `sfx_inventory_open_close` | Inventory open / close | Inventory UI opens or closes | Panel slide + soft click | 2 | P0 |
| `sfx_hotbar` | Hotbar select / scroll | Hotbar slot changes | Short tick/click | 2 | P0 |
| `sfx_item_move` | Move/stack/delete item | Drag item between slots; split stack; trash | Soft pick/place click, trash crumple | 2-3 | P1 |
| `sfx_chest` | Chest open/close | Chest UI opens/closes; rare chest found | Wood latch, lid creak, close thud; rare chest sparkle | 3-4 | P1 |
| `sfx_door` | Door open/close | Placeable door toggles | Latch click + wood swing/close | 2 | P1 |
| `sfx_bonfire` | Bonfire ignite/extinguish/toggle | Bonfire plain-click sets or clears respawn | Whoosh, crackle burst, soft extinguish | 2-3 | P1 |
| `sfx_torch` | Torch place/remove | Torch placed or mined | Soft plant/light pop; remove puff | 2 | P1 |
| `sfx_fishing` | Fishing cast, bite, reel, catch | Rod cast; fish bites; reel starts; catch/miss resolves | Cast whoosh, splash, line tick, reel, catch jingle, miss plop | 6 | P1 |
| `sfx_map_waypoint` | Map/waypoint interactions | Map opens/closes; waypoint selected; travel starts/arrives | Map unfold, marker click, charge hum, teleport whoosh, arrival settle | 4-6 | P1 |
| `sfx_water` | Water splash / bucket | Enter/exit water; fill/empty bucket; pour water | Splash, wade, bucket fill, pour | 4 | P1 |
### UI & Progression

| ID | Action | Trigger | Sound direction | Variants | Priority |
|---|---|---|---|---:|---|
| `sfx_ui_interaction` | UI hover/click/back/tab/toggle/slider | Any menu interaction | Pixel click/blip, back, tab, toggle, slider tick; 2-3 variants each | 10-14 | P0 |
| `sfx_ui_result` | Success/error/notification | Action succeeds, fails, or toast appears | Success chime, error buzz, info/success/warn toast | 4-5 | P0 |
| `sfx_menu_pause` | Menu open/close, pause/unpause | Main menu, pause menu, settings, inventory | Panel open/close, pause stop/resume | 4 | P1 |
| `sfx_save_load` | Save/load/delete | Save slot saved, loaded, deleted, or errors | Confirm click, save stamp, load whoosh, delete warning | 4 | P1 |
| `sfx_account_cloud` | Login, signup, logout, cloud sync | Account form submit; cloud sync starts, succeeds, conflicts, fails | Auth success/fail; sync spinner ticks, success, conflict, error | 7-8 | P2 |
| `sfx_leaderboard` | Leaderboard refresh / star claim | Leaderboard loads; mission reward claimed | Refresh tick, star claim chime | 2 | P2 |
| `sfx_mission` | Mission progress / mission complete / star | add_mission_progress; complete_mission; mission_star_earned | Progress tick, completion flourish, star sparkle | 3 | P0 |
| `sfx_knowledge_bestiary` | Knowledge or bestiary unlock | Knowledge entry learned; bestiary entry discovered | Page shimmer, archive stamp, creature reveal | 2-3 | P1 |
| `sfx_tutorial` | Tutorial dialogue/advance/complete/skip | Tutorial opens, advances, finishes, or is skipped | Dialogue open, text advance, success, skip | 4 | P1 |
| `sfx_code_editor` | Code editor open/run/stop/success/error | Lua/Python editor opens; RUN/STOP; program succeeds/fails | Panel open, run start, terminal tick, success chime, error buzz, stop | 6 | P1 |
| `sfx_quiz` | Quiz open/correct/wrong/hint/run/complete | Quiz altar opens; answer submitted; hint; code run; results | Panel open, correct, wrong, hint, run, completion | 6 | P1 |
| `sfx_knowledge_altar` | Knowledge altar open/page/unlock | Altar opens; page turns; entry unlocks | Stone open, page turn, unlock shimmer | 3 | P2 |
| `sfx_color_crafter` | Color select/craft | Color wheel changes; colored block crafted | Color tick, hue chime, craft pop | 2-3 | P1 |
### Crafting & Automation

| ID | Action | Trigger | Sound direction | Variants | Priority |
|---|---|---|---|---:|---|
| `sfx_station` | Crafting station open/close | Crafting station UI opens/closes | Wood/metal panel open, close latch | 2 | P1 |
| `sfx_recipe_select` | Recipe selected | Recipe list selection changes | Soft page/click tick | 2 | P1 |
| `sfx_craft` | Craft start/complete/fail | craft() / craft_request starts, finishes, or fails | Work start, hammer/craft completion, error buzz | 3-4 | P0 |
| `sfx_station_io` | Input insert / output collect | Input slot loaded; output taken | Item drop into slot; output pickup/chime | 2 | P1 |
| `sfx_furnace` | Furnace open/close, feed, fuel, smelt, fail | Furnace UI opens; feed/fuel; smelt starts/tick/completes/fails | Lid, ore drop, fuel whoosh, fire loop, metal clink, error | 7-9 | P1 |
| `sfx_lua_station` | Lua station place/editor open/close | LUA station placed; editor opens/closes | Robot boot chirp, panel open, panel close | 3 | P1 |
| `sfx_lua_run` | Automatica run start/success/error/stop | Run pressed; program executes; error; STOP | Terminal run, success beep, error buzz, stop clunk | 4 | P1 |
| `sfx_robot_move` | Robot movement/hover | Robot is moving or hovering | Soft servo loop or periodic hover tick | 1 loop | P2 |
| `sfx_robot_work` | Robot chop/mine/place | Robot performs chop, mine, or placement | Servo + wood/stone impact; build placement | 6-8 | P1 |
| `sfx_robot_combat` | Robot attack/hurt/death | Robot swings, takes damage, dies/terminates | Metal swing, hit, damage clank, shutdown | 4-5 | P1 |
| `sfx_robot_logistics` | Robot deposit/withdraw/return/home | Robot deposits to chest, withdraws, or returns to station | Item transfer ticks, servo turn, docking clunk | 4 | P2 |
| `sfx_robot_error` | Robot error/no tool/invalid request | No tool equipped; invalid target; no chest/space | Robot error chirp + UI error | 2 | P1 |
| `sfx_algorithmica` | Algorithmica run start/success/error/reject | Python program runs, succeeds, fails, or uses a foreign API | Terminal run, success chime, error buzz, rejection buzz | 4 | P1 |
| `sfx_algorithmica_color` | Color craft | craft_color() succeeds or fails | Hue pop/chime; low cactus error | 2 | P1 |
### Combat & Mobs

| ID | Action | Trigger | Sound direction | Variants | Priority |
|---|---|---|---|---:|---|
| `sfx_mob_wolf` | Wolf voice set | Wolf idle/ambient, attack, hurt, and death | growl, bite snap, yelp, death whine | 3-5 | P1 |
| `sfx_mob_pixie` | Pixie voice set | Pixie idle/ambient, attack, hurt, and death | glassy chime, dart, cry, death sparkle | 3-5 | P1 |
| `sfx_mob_worm` | Desert Worm voice set | Desert Worm idle/ambient, attack, hurt, and death | burrow rumble, emerge, lunge, death | 3-5 | P1 |
| `sfx_mob_headless_fish` | Headless Fish voice set | Headless Fish idle/ambient, attack, hurt, and death | wing flap, bite, hurt, death | 3-5 | P1 |
| `sfx_mob_sheep` | Sheep voice set | Sheep idle/ambient, attack, hurt, and death | bleat, hurt, death | 3-5 | P2 |
| `sfx_mob_hitman` | Hitman voice set | Hitman idle/ambient, attack, hurt, and death | heavy footstep, roar, slam, projectile, hurt, defeat | 3-5 | P1 |
| `sfx_mob_rune_sentinel` | Rune Sentinel voice set | Rune Sentinel idle/ambient, attack, hurt, and death | stone grind, slam, hurt, death | 3-5 | P1 |
| `sfx_mob_brass_prowler` | Brass Prowler voice set | Brass Prowler idle/ambient, attack, hurt, and death | mechanical skitter, swipe, hurt, death | 3-5 | P1 |
| `sfx_mob_cinder_ooze` | Cinder Ooze voice set | Cinder Ooze idle/ambient, attack, hurt, and death | bubble, spit, hurt, death | 3-5 | P1 |
| `sfx_mob_cipher_warden` | Cipher Warden voice set | Cipher Warden idle/ambient, attack, hurt, and death | digital hum, cast, hurt, death | 3-5 | P1 |
| `sfx_mob_gravebell_shambler` | Gravebell Shambler voice set | Gravebell Shambler idle/ambient, attack, hurt, and death | bell rattle, swipe, hurt, death | 3-5 | P1 |
| `sfx_mob_emberfox_kit` | Emberfox Kit voice set | Emberfox Kit idle/ambient, attack, hurt, and death | chirp, pounce, hurt, death | 3-5 | P2 |
| `sfx_mob_mossback_nib` | Mossback Nib voice set | Mossback Nib idle/ambient, attack, hurt, and death | nibble, charge, hurt, death | 3-5 | P2 |
| `sfx_mob_vesper_acolyte` | Vesper Acolyte voice set | Vesper Acolyte idle/ambient, attack, hurt, and death | chant, cast, hurt, death | 3-5 | P1 |
| `sfx_mob_wisp` | Wisp companion voice set | Wisp companion idle/ambient, attack, hurt, and death | soft chime, follow loop, hurt, fade | 3-5 | P2 |
| `sfx_mob_spawn_despawn` | Mob spawn/despawn | A mob appears in view or is recycled off-screen | Soft spatial pop/whoosh; avoid off-screen churn | 2 | P2 |
| `sfx_hitman_specials` | Hitman projectile, slam, self-destruct | Hitman fires, slams, or self-destructs | Projectile launch, impact, heavy slam, explosion | 4 | P1 |
| `sfx_dungeon_hazards` | Dungeon flare/projectile/trap/explosion | Flare fires; projectile flies/impacts; trap steps; explosion | Vent whoosh, bolt launch, sizzle, click, blast | 6-8 | P0 |
| `sfx_parry_safezone` | Parry projectile / safe-zone ward | Sword parries a bolt; safe zone activates or pulses | Metal ting, safe-zone hum, ward pulse | 3 | P1 |
### World & Dungeon

| ID | Action | Trigger | Sound direction | Variants | Priority |
|---|---|---|---|---:|---|
| `sfx_cave_travel` | Enter/exit cave | Cave portal confirms; player enters or leaves cave | Stone slide, echo, distant drip, exit gust | 2-3 | P1 |
| `sfx_cave_portal` | Cave entrance highlight/confirm | Player nears a cave mouth; confirms entry | Low rumble, highlight ping, confirm click | 2-3 | P2 |
| `sfx_dungeon_portal` | Dungeon portal enter/exit | Dungeon portal activates, entered, or exited | Rune hum, portal whoosh, arrival thud | 3 | P1 |
| `sfx_dungeon_clear` | Dungeon clear / star award | Dungeon cleared; 1/2/3-star result | Clear fanfare, star chime, perfect-clear shimmer | 4 | P0 |
| `sfx_world_waypoint` | World waypoint activate/travel | Tower activated; travel charge; arrival | Crystal chime, charge loop, teleport whoosh, arrival | 3-4 | P1 |
| `sfx_dungeon_waypoint` | Dungeon waypoint spawn/activate | Temporary waypoint appears; activated | Rune spawn, activation ping | 2 | P2 |
| `sfx_day_night` | Day/night transition | Dawn or dusk changes the world state | Soft wind/chime transition | 2 | P2 |
| `sfx_snowstorm` | Snowstorm start/end | Snowstorm begins or ends | Wind rise, wind fade, snow crunch layer | 2-3 | P2 |
| `sfx_ambient_birds` | Ambient bird chirps | Day/night ambient birds appear | Finch/kite chirp variants | 4-6 | P2 |
| `sfx_cave_ambience` | Cave ambience | Player is inside a cave | Drips, low echo, distant stone settles | 1 loop | P2 |
| `sfx_dungeon_ambience` | Dungeon ambience | Player is inside a dungeon | Low rune hum, torch crackle, distant stone | 1 loop | P2 |
| `sfx_fire_ambience` | Torch/bonfire ambience | Player near lit torch/bonfire | Small flame crackle loop | 1-2 loops | P2 |
| `sfx_weather_wind` | Generic wind/weather bed | Exposed overworld, snowy biome, storm | Soft wind loop; snowstorm variant | 2 loops | P2 |

## Implementation notes for later

- Add separate `Music` and `SFX` buses before wiring sounds; keep the existing master/music/sfx sliders meaningful.
- Use one SFX manager/pool rather than one `AudioStreamPlayer` per object; highly overlapping cues (mining, footsteps, UI) need voice limiting.
- Randomize pitch/volume slightly for repeated cues; do not stack identical samples on the same frame.
- Spatialize world SFX and keep UI/editor sounds non-spatial.
- Add accessibility controls for low-health heartbeat, ambience, and UI sound volume.
- Loop ambience seamlessly and duck it under combat/cutscenes; BGM is out of scope.
