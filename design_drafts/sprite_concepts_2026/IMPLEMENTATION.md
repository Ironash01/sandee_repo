# Bestiary Update — Applied Creature Notes

This document records the implementation pass that followed the sprite concept
draft. It is deliberately kept outside production runtime assets.

The six point-and-click cursors have also been applied; their runtime director
is `SandEEAlpha/scripts/cursor_manager.gd` and the approved PNGs live in
`SandEEAlpha/sprites/ui/cursors/`.

## What was applied

The following eight concepts now exist as production gameplay creatures:

| Creature | Runtime scene | Data resource | Native sheet |
|---|---|---|---|
| Mossback Nib | `scenes/mobs/MossbackNib.tscn` | `resources/mobs/mossback_nib.tres` | 32×32 |
| Emberfox Kit | `scenes/mobs/EmberfoxKit.tscn` | `resources/mobs/emberfox_kit.tres` | 48×48 |
| Cinder Ooze | `scenes/mobs/CinderOoze.tscn` | `resources/mobs/cinder_ooze.tres` | 48×48 |
| Gravebell Shambler | `scenes/mobs/GravebellShambler.tscn` | `resources/mobs/gravebell_shambler.tres` | 48×48 |
| Rune Sentinel | `scenes/mobs/RuneSentinel.tscn` | `resources/mobs/rune_sentinel.tres` | 64×64 |
| Vesper Acolyte | `scenes/mobs/VesperAcolyte.tscn` | `resources/mobs/vesper_acolyte.tres` | 48×64 |
| Brass Prowler | `scenes/mobs/BrassProwler.tscn` | `resources/mobs/brass_prowler.tres` | 64×48 |
| Cipher Warden | `scenes/mobs/CipherWarden.tscn` | `resources/mobs/cipher_warden.tres` | 64×64 |

The runtime sheets and Bestiary portraits are in:

`SandEEAlpha/sprites/mobs/bestiary/`

## Animation

Each runtime sheet is a **5-column × 4-row** grid:

- rows: **south, north, east, west**
- columns: **idle + four walk frames**

The shared actor (`scripts/bestiary_mob.gd`) slices the sheet into `AtlasTexture`
frames at runtime. Every creature has `idle_<direction>` and
`walk_<direction>` animations for all four cardinal directions, and each walk
cycle uses four frames. Diagonals use the dominant axis, which is the accepted
fallback requested for this pass. Emberfox, Mossback Nib and Brass Prowler use
dedicated alternating-leg gait frames; Cinder Ooze, Gravebell, Vesper, and the
floating constructs use four-frame squash, shamble/sway and hover cycles.

Hostile creatures use the existing raycast-guided `PIXIE` steering for chase
and obstacle avoidance. The two friendly creatures use the new
`scripts/AI/WANDER.gd` clear-path wander AI, so trees, placed blocks and dungeon
pillars do not stall them; both paths still use the actor's water-footprint
veto where water exists.

The concept contact sheet is
`previews/directional_sheets.png`; the in-game sheets are one PNG per creature.

## Scaling

Overworld creatures use a **1.15× visual scale** with matching scaled
collision/hitboxes:

- Mossback Nib
- Cinder Ooze
- Gravebell Shambler

**Emberfox Kit is scaled to 0.58×** (roughly half of its previous 1.15×
on-screen size), with its collision, shadow and foot anchor scaled by the same
factor.

Dungeon creatures use their native 1.0× scale, matching the existing 64 px
Hitman-class dungeon enemies. Sprite offsets align each creature's feet with
the shared foot/collision anchor; y-sort uses the same anchor.

## Spawning

### Overworld

`world.gd` adds the four overworld creatures to the ambient spawn pool:

- **Mossback Nib** — passive plains grazer, small herd spawn
- **Emberfox Kit** — passive plains/snowy fox kit
- **Cinder Ooze** — hostile ooze, plains
- **Gravebell Shambler** — hostile undead, plains

### Dungeons

`dungeon_world.gd` replaces the ordinary theme-agnostic regular Hitman spawn
pool with theme-specific creatures:

- **Lua:** Rune Sentinel / Vesper Acolyte
- **Python:** Brass Prowler / Cipher Warden

The tutorial (enemy-free) dungeons, quiz guards, and the Hitman miniboss remain
unchanged. New dungeon creatures receive the `DungeonHostile` group so they
count against the existing alive cap and are handled by safe-zone protection.

## Bestiary behavior

The tab is a sibling of Inventory, Craft and Encyclopedia inside
`scripts/inventory_ui.gd`.

- **Sighting:** `Global._process()` scans live `"Mob"` nodes at most once every
  0.3 s. A creature must be visible on screen. The first sighting records only
  its catalogue id, shows a notification with its name, and emits
  `bestiary_updated`.
- **Study:** the first real kill records the entry as studied and posts a
  "Bestiary entry studied/completed" notification. Deaths caused by safe-zone
  disintegration or despawn do **not** count.
- **Details:** a seen entry shows name and portrait. After the first kill the
  tab shows the description, maximum health, and every drop entry with item
  icon, quantity range and chance.
- **Persistence:** `bestiary_seen` and `bestiary_killed` are stored in
  `save_slot_N.json`. Existing saves without those keys load with empty
  Bestiary state; no migration of unrelated save data is required.
- **Catalog:** `scripts/bestiary_catalog.gd` scans
  `res://resources/mobs/*.tres` for non-empty `bestiary_id` values, so future
  creatures only need data fields and a scene/pool entry.

This first Bestiary pass catalogues the **eight new creatures**. Legacy
creatures (sheep, worms, pixies, etc.) are not retrofitted into the tab in this
pass; doing so would require adding their own curated descriptions/drops and
legacy kill hooks.

## Drops

Drops use existing SandEE item resources; no item definitions or loot tables
were invented in the game files. The first matching drop is guaranteed where
`chance` is 1.0; independent rolls are used for the others.

| Creature | Drops |
|---|---|
| Mossback Nib | Wheat Seeds 1–2 (85%), White Fur 1 (40%), Stick 1 (25%) |
| Emberfox Kit | Dog Meat 1–2 (Always), White Fur 1 (55%), Stick 1 (20%) |
| Cinder Ooze | Charcoal 1–3 (Always), Copper Ore 1–2 (45%), Stone 1–2 (35%) |
| Gravebell Shambler | Copper 1–2 (Always), Charcoal 1–2 (60%), Iron Ore 1 (20%) |
| Rune Sentinel | Stone 2–4 (Always), Copper 1–2 (65%), Crystal Silicon Ore 1 (25%) |
| Vesper Acolyte | Charcoal 1–3 (Always), Copper 1 (40%), Crystal Silicon Ore 1 (15%) |
| Brass Prowler | Copper 1–3 (Always), Ironbar 1 (50%), Silicon 1 (30%), Wire 1–2 (40%) |
| Cipher Warden | Silicon 1–3 (Always), CPU 1 (25%), Diamond 1 (8%), Crystal Silicon Ore 1 (30%) |

## Verification

- Headless editor import/parse validation: no new script/resource errors.
- Regression suite: **580/580 passed** (the 565 existing checks plus 15
  Bestiary checks).
- The temporary development test scenes and save slot were removed after
  validation.

Nothing was committed, pushed, version-bumped, or exported as an APK.
