# SandEE dungeon tileset revision - design draft 01

Status: **approved and applied**. The tile, interior, and animation direction is
now integrated into `DungeonWorld`; see `IMPLEMENTATION.md` for production paths,
behavior, animation details, and verification. This README remains the original
design/review document. The draft pass itself did not alter the existing
production assets it inspected; the implementation was a separate approved step.

This is the review package for two distinct language-dungeon art directions:

- **Lua - Ancient Rune Sanctum**
- **Python - Stonegate Foundry**

Both take their architecture, materials, metalwork, and magic-light vocabulary
from the approved waypoint drafts, while remaining part of SandEE's existing
32 px dungeon family.

## What was inspected

### Existing production dungeon art

- `SandEEAlpha/sprites/dungeon/SandEE_alpha_dungeontilesets.png` - one shared
  512 x 512 dungeon source sheet.
- Wall entry icons use 32 x 32 AtlasTexture regions:
  - top-left / top-mid / top-right
  - mid-left / mid-right
  - bottom-left / bottom-mid / bottom-right
- Floor icons use three 32 x 32 regions.
- `DungeonWorld` draws a 3 x 3 wall face set (top band, buried middle band,
  bottom band) with the existing eight wall variants; the current middle-center
  mapping reuses the top-middle sprite.
- Existing dungeon interiors are limited to 32 x 32 icon props (Knowledge/Quiz
  Altars, flare, trap, safe-zone marker) plus procedural room/corridor generation.
- There is **no separate production Lua dungeon tileset or Python dungeon
  tileset** in the current project. The language distinction currently comes
  from the mission/resource content, not from the dungeon TileSet. This draft
  supplies that missing visual distinction.
- Dungeon rooms are generated on a 32 px tile grid; current rooms are roughly
  6-8 tiles across before corridors and bonus rooms.

### Waypoint references used

- `design_drafts/waypoints/revised/sprites/portal_lua_ancient_animated_sheet.png`
  - 1536 x 160, eight 192 x 160 frames at 10 fps.
- `design_drafts/waypoints/revised/sprites/portal_python_stonegate_animated_sheet.png`
  - 1280 x 128, eight 160 x 128 frames at 10 fps.
- Both use the existing SandEE pixel density, black mortar outlines, gold trim,
  and language-specific magic light.

## Deliverables

### Preview files

| File | Contents |
| --- | --- |
| `previews/lua_tiles_and_architecture.png` | Lua wall/floor tile draft, assembled wall/floor patch, isolated architecture, waypoint reference, palette and design intent |
| `previews/lua_interior_mockup.png` | Lua interior assembled from the proposed tiles and architecture, with illustrative lighting |
| `previews/python_tiles_and_architecture.png` | Python wall/floor tile draft, assembled wall/floor patch, isolated architecture, waypoint reference, palette and design intent |
| `previews/python_interior_mockup.png` | Python interior assembled from the proposed tiles and architecture, with illustrative lighting |
| `previews/lua_waypoint_comparison.png` | Lua waypoint vs proposed interior, side by side with a palette link |
| `previews/python_waypoint_comparison.png` | Python waypoint vs proposed interior, side by side with a palette link |
| `previews/palette_materials.png` | Combined material boards, hex swatches, and native 32 px material chips |
| `previews/tileset_organization.png` | Proposed atlas layout and dimensions |
| `previews/existing_style_reference.png` | Read-only inspection sheet for the current shared production dungeon TileSet; shows why a new per-language direction is being proposed |
| `implementation_previews/` | Applied in-game theme screenshots and animated sconce/medallion GIF previews |

### Transparent isolated source art

- `sprites/lua_walls_floors_transparent.png`
- `sprites/lua_architecture_transparent.png`
- `sprites/python_walls_floors_transparent.png`
- `sprites/python_architecture_transparent.png`
- Individual native tiles and props in `sprites/lua/` and `sprites/python/`.

The native mockups are also saved as
`sprites/lua_interior_mockup_native.png` (640 x 384) and
`sprites/python_interior_mockup_native.png` (640 x 384).

## Proposed dimensions and atlas organization

### Walls - 32 x 32 px

The draft retains the existing 3 x 3 face-set convention:

| Cell | Role |
| --- | --- |
| top-left / top-mid / top-right | lit top cap and upper wall face |
| mid-left / mid-mid / mid-right | buried middle band; side bevels |
| bottom-left / bottom-mid / bottom-right | shadowed base/footing |

- 9 primary wall cells.
- 2 alternate brick cells per theme: a carved rune/diamond variant and a worn
  variant.
- Proposed wall atlas: **11 cells x 1 row = 352 x 32 px** per theme.
- Until a later code change is approved, the existing mapping can keep using
  top-mid for middle-center; the distinct mid-mid cell is an optional improvement.

### Floors - 32 x 32 px

- 3 primary floor variations.
- 2 subtle alternates.
- 4 edge transitions (N/E/S/W) and 4 corner transitions.
- Proposed floor atlas: **13 cells x 1 row = 416 x 32 px** per theme.
- Edge/corner tiles use a transparent outer strip and a 1 px floor lip; they are
  optional and only needed where a raised platform edge is desired.

### Architecture props - transparent isolated sprites

| Prop | Native size | Intended use |
| --- | --- | --- |
| Pillar | 32 x 96 | free-standing support; base, shaft, capital |
| Pilaster | 32 x 64 | attached wall support |
| Door frame | 96 x 96 | 3 x 3 doorway surround with transparent opening |
| Blind arch | 96 x 64 | carved wall niche; solid recess with motif |
| Masonry panel | 64 x 32 | 2 x 1 decorative wall masonry |
| Sconce | 16 x 32 | wall-mounted light fixture |
| Floor medallion | 64 x 64 | 2 x 2 circular/diamond floor motif |

These should be a separate **props layer** when implemented. They are deliberately
not baked into the 32 x 32 TileSet, because the current dungeon renderer only
paints tile cells and would need an explicit reviewed placement step.

## Lua - Ancient Rune Sanctum

**Identity:** a tall, ceremonial basalt sanctuary built around pointed arches,
thin gold rails, and a cold crescent-blue magical light.

**Materials**

- Warm charcoal-violet basalt, irregular ashlar courses.
- Black mortar and sparse chipped edges.
- Antique gold limited to thresholds, capitals, rails, and ritual inlays.
- Violet magic with rare cold-blue crescent highlights.
- Thin green moss flecks in damp mortar joints.

**Palette**

| Swatch | Hex | Role |
| --- | --- | --- |
| stone shadow | `#241E2A` | deep recess |
| stone dark | `#322A3A` | mortar-side blocks |
| stone base | `#403646` | primary brick |
| stone light | `#62546C` | chipped face / cap |
| stone high | `#806C8A` | top-edge highlight |
| floor base | `#3B3347` | processional flagstone |
| floor light | `#554965` | slab bevel |
| floor shadow | `#211A2A` | seam/shadow |
| gold dark | `#73562B` | deep metal line |
| gold | `#C09A55` | rails and frames |
| gold high | `#F1D692` | metal glint |
| magic deep | `#2B1855` | portal/door recess |
| magic | `#8064E0` | rune light |
| magic high | `#C0A6FF` | lit rune edge |
| magic glow | `#F0E8FF` | inner glow |
| accent blue | `#7FD0FF` | crescent glint |

**Architecture**

- Pointed door and blind arch silhouettes.
- Clustered narrow pillars with gold collars and violet rune channels.
- Circular rune medallions and concentric floor rings.
- Large, fewer floor flags rather than a small square grid.
- Sparse crescent carving and vertical gold rails.

## Python - Stonegate Foundry

**Identity:** a heavy blue-grey ashlar foundry-vault with round arches, brass
bands, square rivets, and teal crystal light. It is intentionally heavier and
more modular than the Lua sanctuary.

**Materials**

- Cool blue-grey ashlar with broad rectangular blocks.
- Black mortar and beveled block corners.
- Brass bands, square studs, and stepped bases.
- Teal/cyan crystal inlays and local light pools.
- Restrained green moss in joints and floor aggregate.

**Palette**

| Swatch | Hex | Role |
| --- | --- | --- |
| stone shadow | `#18242D` | recess / foot |
| stone dark | `#24323C` | secondary block |
| stone base | `#30414C` | primary block |
| stone light | `#526875` | top bevel |
| stone high | `#708C98` | edge highlight |
| floor base | `#2B3B45` | foundry slab |
| floor light | `#415A65` | slab bevel |
| floor shadow | `#14222A` | seam/shadow |
| gold dark | `#73562B` | deep brass |
| gold | `#C09A55` | bands / frames |
| gold high | `#F1D699` | rivet glint |
| magic deep | `#0A3B3D` | crystal recess |
| magic | `#2FA9A0` | teal inlay |
| magic high | `#7DF0DF` | crystal edge |
| magic glow | `#D8FFF7` | inner glow |
| moss | `#536F44` | weathering |

**Architecture**

- Round arches and heavy square supports.
- Broad brass bands, square rivets, and stepped plinth bases.
- Diamond shard floor medallion and geometric wall panels.
- 16 px foundry slab rhythm instead of Lua's large flags.
- Teal/cyan crystal brackets and local teal light pools.

## Shared rules / what stays consistent

- 32 px tile grid; no smoothing or mixed pixel density.
- 1 px mortar/outline language and restrained highlight count.
- Gold is the common SandEE metal family; each language owns its magic hue.
- Floors remain low-contrast enough that characters, enemies, traps, and
  projectiles stay readable.
- Architecture details are deliberately sparse; large motifs live on props and
  medallions rather than every brick.
- No functional object, mechanic, collision change, or generation rule is drafted
  here.

## Review checklist

1. Does Lua read immediately as the pointed/ritual counterpart to its waypoint?
2. Does Python read as the heavier foundry counterpart without becoming a
   simple recolor of Lua?
3. Are wall, floor, and accent values sufficiently separated at normal game zoom?
4. Are the 3 x 3 wall-face connections and floor edge transitions convincing in
   the assembled sample?
5. Are the large props and the 20 x 12 room proportions appropriate for the
   existing dungeon scale?
6. Should any of the extra floor variants, alternate wall variants, or edge
   transitions be dropped to keep implementation scope small?

## Known limitations

- Only a shared production dungeon tileset exists; this draft is the first
  proposed per-language dungeon art direction, not a revision of an existing
  language-specific set.
- Approved architecture is now applied as room props. Side/bottom door-frame
  orientations remain future work; the current implementation uses top-wall
  openings only.
- The mockup lighting is illustrative; the implementation uses a theme-specific
  `CanvasModulate` plus local sconce/medallion lights, not the mockup gradients.
- In-game desktop rendering was checked at the normal 1.9 camera zoom. Android
  capture and safe-area validation remain outstanding.
- Tiles, props, and sprite previews use nearest-neighbour enlargement only.
  The soft lighting overlays in the interior mockups are illustrative gradients,
  not a proposed shader or light-node implementation. These are not production
  atlas files.

## Generator

`build_dungeon_tilesets.py` regenerates every image in this folder. It reads the
approved waypoint drafts as visual references and writes only under this draft
directory.

No APK was exported, no version was changed, and no commit or push was made.
