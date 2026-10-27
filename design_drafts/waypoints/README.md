# SandEE — Waypoint Visual Drafts

**Status: visual concept only. Not implemented in the game.**

> **Revision 2 is in `revised/`.** It selects Stonegate for Python, Ancient Rune
> Gate for Lua, and the animated Ruined Skyglass Tower as the only world
> waypoint. The original four-concept sheet below is retained as review history.

These are review drafts for two waypoint families. They are intentionally kept
outside `SandEEAlpha/` so no draft PNG is imported into the production project
and no gameplay scene, asset, save, or world-generation code is touched.

## Draft deliverables

| File | Purpose |
| --- | --- |
| `waypoint_closeups.png` | Labelled close-up sheet for all four designs + existing block swatches |
| `waypoint_world_mock.png` | Approximate in-world placement at the game's 1.9× camera zoom |
| `waypoint_silhouettes.png` | Common-scale silhouette comparison |
| `sprites/portal_primary.png` | Transparent 160×128 isolated sprite |
| `sprites/portal_alt_ancient.png` | Transparent 192×160 isolated sprite |
| `sprites/tower_primary.png` | Transparent 128×224 isolated sprite |
| `sprites/tower_alt_ruined.png` | Transparent 160×224 isolated sprite |
| `sprites/*_x4.png` | Nearest-neighbour close-up exports |
| `build_waypoint_drafts.py` | Rebuilds the PNG previews from code |

## 1. Dungeon waypoint — Stonegate Portal (primary)

- **Native size:** 160×128 px, 5×4 tiles (32 px per tile)
- **Pivot/anchor:** bottom-centre; the portal threshold is the walkable focal cell
- **Materials referenced:** Stone, Granite, Sandstone trim, Wood; existing dungeon
  portal cyan/violet/green magic palette
- **Design choices:** compact gatehouse silhouette, stepped base, rounded stone
  arch, carved gold runes, embedded side crystals, teal portal veil. The crest
  gem and rim glow make it read as a magical gateway rather than a normal door.

## 2. Dungeon waypoint — Ancient Rune Gate (alternative)

- **Native size:** 192×160 px, 6×5 tiles
- **Pivot/anchor:** bottom-centre
- **Materials referenced:** Stone, Granite, Diorite, Sandstone trim, Gold rune
  inlays, existing dungeon-portal violet/green palette
- **Design choices:** older, broken megalithic gate; pointed arch; twin purple
  crystal obelisks; asymmetric damaged crown and rubble. Purple/violet veil
  distinguishes it from the primary cyan portal.

## 3. World waypoint — Beacon Tower (primary)

- **Native size:** 128×224 px, 4×7 tiles
- **Pivot/anchor:** bottom-centre
- **Materials referenced:** Stone, Granite, Diorite, Sandstone/gold trim, Wood
  braces and banner rod; warm torch/lantern palette
- **Design choices:** strong vertical silhouette with stepped plinth, narrow
  shaft, crenellated watch balcony, belfry chamber, pitched stone cap, and a
  gold finial. The amber hanging lantern is the distance-readable waypoint
  beacon. A small teal banner with a chart-diamond sigil adds a non-house
  landmark detail. A gold compass/rune medallion marks the base.

## 4. World waypoint — Ruined Skyglass Tower (alternative)

- **Native size:** 160×224 px, 5×7 tiles
- **Pivot/anchor:** bottom-centre
- **Materials referenced:** Stone, Granite, Diorite, Wood, existing cave/dungeon
  teal-green magic palette
- **Design choices:** broken watchtower with a split crown, large arched window,
  exposed wooden brace, rubble base, and a floating cyan **skyglass** crystal
  held in a partial rune ring. The teal crystal beacon clearly separates it
  from the amber primary tower and from dungeon portal magic.

## Style notes

- All structures are aligned to the existing 32 px world-tile grid.
- 1 px dark outlines, three-to-five value stone ramps, chunky 2×2/3×3 pixel
  clusters, sparse moss and weathering.
- The portal palettes are sampled from the existing dungeon portal (violet,
  cyan, pale green). The stone values are based on Stone/Granite/Diorite assets.
- The preview mock uses the existing tree, player, and grass assets only for
  scale/context; no production asset is altered or overwritten.

## Deliberately not included

- No waypoint interaction, teleportation, map marker, save data, navigation,
  spawning, dungeon connection, or world-generation implementation.
- No `.tres` structure resources, scenes, or game scripts for these designs yet.
