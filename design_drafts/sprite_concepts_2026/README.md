# SandEE Sprite Concept Draft — Mobs, Birds, Wisp, Cursors & Legendary Items

**Status: split draft. The eight Bestiary creatures (friendly mobs, overworld enemies and Lua/Python dungeon enemies) and both atmospheric birds (Sunshard Finch and Dusk Kite) have been applied as production gameplay creatures. The six point-and-click cursors are also applied in production. The wisp and legendary-item concepts below remain drafts only.**

See [`IMPLEMENTATION.md`](IMPLEMENTATION.md) for the applied scope, animation
format, spawn integration, Bestiary behavior, drops and verification.

- **Game version:** unchanged (`0.9.4.0`)
- **Save format:** extended with optional Bestiary keys; old saves load safely
- **APK/export:** not produced
- **Commit/push:** not performed

All new artwork lives in:

`design_drafts/sprite_concepts_2026/`

The draft is intentionally outside `SandEEAlpha/`.

---

## 1. Existing-style inspection

The actual in-project reference sheet is:

- [`reference/existing_style_inspection.png`](reference/existing_style_inspection.png)

It includes the current sheep, wolf, slime, pixie, Hitman, headless fish, world waypoint, inventory icons and style notes.

### Measured project constraints

| Reference | Native size / note |
|---|---|
| World tile grid | **32 px** |
| Sheep frame | 32×32 |
| Wolf frame | 48×48 |
| Hitman frame | 64×64 |
| Pixie frame | 64×64 |
| Slime frame | 96×96 sheet frame; visible cyan blob is about 50 px wide |
| Headless fish frame | 49 px high (wide multi-frame sheet) |
| Inventory item icons | 32×32 |
| World waypoint sheet | 224×224 frame crop; dark stone + teal crystal |

The existing style uses:

- 1 px dark outlines and dark interior accents
- small, readable silhouettes at gameplay scale
- flat, limited palettes with 2–4 tone shading
- very few anti-aliasing-style colour transitions
- chunky, hand-placed pixel forms
- simple facial features, usually just dark eyes and a small mouth mark

### Environment reference

- **Overworld:** bright saturated grass, simple 32 px ground treatment, large round trees, small stone ruins and tiny ambient sheep. The mockups use a real capture from the project's title panorama as a representative sandbox.
- **Lua dungeon:** near-black violet masonry, pointed arches, gold trim, sconces, medallions, violet rune light.
- **Python dungeon:** slate-blue ashlar, brass fixtures, teal diamond crystals and mechanical detailing.
- **Waypoint:** dark stone tower with a large teal diamond crystal. See [`reference/waypoint_reference.png`](reference/waypoint_reference.png).

### Missing reference assets / documented limitations

1. **No zombie sprite or zombie scene exists in the project.** The Gravebell Shambler therefore uses the hostile humanoid proportions of the existing 64×64 Hitman frame as a structural reference while staying organic and overworld-scaled. The existing slime is the reference for the slime-variant silhouette.
2. **No custom cursor asset existed at audit time.** The only cursor-related configuration found was the default OS pointer and `CURSOR_POINTING_HAND` used by an encyclopedia header. The cursor set below is now applied in production.
3. The reference overworld capture is a runtime screenshot copied into this draft as art context. It is not a live scene export and is not used by the generator at runtime.

---

## 2. Deliverable index

### Raw transparent sprites

| Category | Concept | Native canvas | Raw sprite | Animation strip |
|---|---|---:|---|---|
| Friendly mob | Mossback Nib | 32×32 | [`sprites/friendly_mobs/mossback_nib.png`](sprites/friendly_mobs/mossback_nib.png) | [`..._idle_4f.png`](sprites/friendly_mobs/mossback_nib_idle_4f.png) |
| Friendly mob | Emberfox Kit | 48×48 | [`sprites/friendly_mobs/emberfox_kit.png`](sprites/friendly_mobs/emberfox_kit.png) | [`..._idle_4f.png`](sprites/friendly_mobs/emberfox_kit_idle_4f.png) |
| Overworld enemy | Cinder Ooze | 48×48 | [`sprites/overworld_enemies/cinder_ooze.png`](sprites/overworld_enemies/cinder_ooze.png) | [`..._idle_4f.png`](sprites/overworld_enemies/cinder_ooze_idle_4f.png) |
| Overworld enemy | Gravebell Shambler | 48×48 | [`sprites/overworld_enemies/gravebell_shambler.png`](sprites/overworld_enemies/gravebell_shambler.png) | [`..._idle_4f.png`](sprites/overworld_enemies/gravebell_shambler_idle_4f.png) |
| Lua dungeon enemy | Rune Sentinel | 64×64 | [`sprites/lua_enemies/rune_sentinel.png`](sprites/lua_enemies/rune_sentinel.png) | [`..._idle_4f.png`](sprites/lua_enemies/rune_sentinel_idle_4f.png) |
| Lua dungeon enemy | Vesper Acolyte | 48×64 | [`sprites/lua_enemies/vesper_acolyte.png`](sprites/lua_enemies/vesper_acolyte.png) | [`..._idle_4f.png`](sprites/lua_enemies/vesper_acolyte_idle_4f.png) |
| Python dungeon enemy | Brass Prowler | 64×48 | [`sprites/python_enemies/brass_prowler.png`](sprites/python_enemies/brass_prowler.png) | [`..._idle_4f.png`](sprites/python_enemies/brass_prowler_idle_4f.png) |
| Python dungeon enemy | Cipher Warden | 64×64 | [`sprites/python_enemies/cipher_warden.png`](sprites/python_enemies/cipher_warden.png) | [`..._idle_4f.png`](sprites/python_enemies/cipher_warden_idle_4f.png) |
| Atmospheric bird | Sunshard Finch | 24×24 | [`sprites/birds/sunshard_finch.png`](sprites/birds/sunshard_finch.png) | [`..._wing_4f.png`](sprites/birds/sunshard_finch_wing_4f.png) |
| Atmospheric bird | Dusk Kite | 32×32 | [`sprites/birds/dusk_kite.png`](sprites/birds/dusk_kite.png) | [`..._wing_4f.png`](sprites/birds/dusk_kite_wing_4f.png) |
| Spectral light | Morrow Wisp | 32×32 | [`sprites/wisp/morrow_wisp.png`](sprites/wisp/morrow_wisp.png) | [`..._frames_4f.png`](sprites/wisp/morrow_wisp_frames_4f.png) |

All raw files have a transparent background. Animation strips are horizontal **4-frame** strips with the same cell size as the base sprite.

### Cursors — 24×24 native

| Action | Raw sprite |
|---|---|
| Movement | [`sprites/cursors/movement.png`](sprites/cursors/movement.png) |
| Open chest | [`sprites/cursors/open_chest.png`](sprites/cursors/open_chest.png) |
| Open crafting | [`sprites/cursors/open_crafting.png`](sprites/cursors/open_crafting.png) |
| Open furnace | [`sprites/cursors/open_furnace.png`](sprites/cursors/open_furnace.png) |
| Open color crafter | [`sprites/cursors/open_color_crafter.png`](sprites/cursors/open_color_crafter.png) |
| Generic interact | [`sprites/cursors/generic_interact.png`](sprites/cursors/generic_interact.png) |

### Legendary items — 32×32 inventory icons

| Item | Proposed theme |
|---|---|
| Starfall Prism | sky-shard artifact in a gold crescent cradle |
| Rootbound Crown | living root-and-leaf circlet with amber heart-gem |
| Eclipse Fang | curved obsidian fang with crescent guard |
| Tideglass Compass | brass wayfinding relic with a blue tideglass lens |
| Ashen Bell | blackened bronze funerary bell with teal rune band |

These are **concept names only**. They are not added to the item registry, do not have stats or effects, and are not in any loot table.

---

## 3. Concept notes

### Friendly mobs — 2

#### Mossback Nib — 32×32

A low, round moss-shelled grazer with a warm tan face, oversized friendly eyes, rose cheeks, small paws, antennae and a tiny mushroom sprout. The shape is deliberately unlike the sheep: a domed shell with a face tucked underneath, plus a leaf tail. The four-frame strip is a soft breathing/bob concept.

- Palette: moss green, cream, warm tan, gold, teal glints
- Read at gameplay size: large eye highlights and the pale face are the first read
- Files: [`raw`](sprites/friendly_mobs/mossback_nib.png) · [`sheet`](previews/friendly_mobs.png) · [`overworld mockup`](previews/friendly_mossback_nib_overworld_mockup.png)

#### Emberfox Kit — 48×48

A sitting rust-orange fox kit with oversized ears, cream chest and muzzle, a curled cream-tipped tail, and a teal neckerchief. The ears and tail make it taller and more alert than the sheep; the rounded paws, big pupils and warm face keep it friendly. Four-frame idle strip.

- Palette: rust, orange highlight, cream, teal, amber
- Read at gameplay size: triangular ears + curled tail; not a wolf recolour
- Files: [`raw`](sprites/friendly_mobs/emberfox_kit.png) · [`sheet`](previews/friendly_mobs.png) · [`overworld mockup`](previews/friendly_emberfox_kit_overworld_mockup.png)

Combined preview: [`previews/friendly_mobs_overworld_mockup.png`](previews/friendly_mobs_overworld_mockup.png)

---

### Overworld enemies — 2

#### Cinder Ooze — 48×48 slime variant

An irregular tar-dark slime with a cooled crust, jagged heat spires, magma seams, two narrowed ember eyes and a bright molten core. It keeps the low ooze footprint of the existing cyan slime but changes the motif from smooth blob to cracked volcanic shell. It is hostile by posture and eye shape, not by gore.

- Palette: charcoal, dark maroon, rust, ember orange, pale yellow
- Contrast: near-black silhouette against bright grass, orange interior accents
- Files: [`raw`](sprites/overworld_enemies/cinder_ooze.png) · [`sheet`](previews/overworld_enemies.png) · [`overworld mockup`](previews/overworld_cinder_ooze_mockup.png)

#### Gravebell Shambler — 48×48 zombie variant

A gaunt green-grey undead bell-ringer in a ragged brown coat, with exposed ribs, one bright amber eye, a hollow socket, stitched jaw, long hanging arm and a corroded handbell. No existing zombie asset was available, so this is the closest hostile-humanoid interpretation using the project's palette and line weight.

- Palette: moss-grey skin, bone, ragged brown, corroded brass, amber
- Read at gameplay size: asymmetric arms + handbell differentiate it from a generic humanoid
- Files: [`raw`](sprites/overworld_enemies/gravebell_shambler.png) · [`sheet`](previews/overworld_enemies.png) · [`overworld mockup`](previews/overworld_gravebell_shambler_mockup.png)

Combined preview: [`previews/overworld_enemies_mockup.png`](previews/overworld_enemies_mockup.png)

---

### Lua dungeon enemies — 2

#### Rune Sentinel — 64×64

A floating armour-shrine: pointed stone pauldrons, a pale mask with violet eye slits, gold inlay, a diamond rune heart, floating claw gauntlets and a tattered lower shrine cloth. It has a broad, symmetrical silhouette and is meant to stand out against near-black violet masonry through pale stone and warm gold.

- Palette: violet-grey stone, pale stone, gold, violet, white core
- Role visual: slow, heavy, magical guardian
- Files: [`raw`](sprites/lua_enemies/rune_sentinel.png) · [`sheet`](previews/lua_enemies.png) · [`room mockup`](previews/lua_rune_sentinel_mockup.png)

#### Vesper Acolyte — 48×64

A tall hooded candle-cultist with a void face, two bright eyes, a gold forehead diamond, a violet flame staff and a tattered robe. Its narrow pointed silhouette contrasts directly with the Sentinel's wide armour.

- Palette: deep violet, muted purple, gold, violet flame, pale white
- Role visual: ceremonial, fragile-looking but clearly hostile
- Files: [`raw`](sprites/lua_enemies/vesper_acolyte.png) · [`sheet`](previews/lua_enemies.png) · [`room mockup`](previews/lua_vesper_acolyte_mockup.png)

Combined room mockup: [`previews/lua_enemies_mockup.png`](previews/lua_enemies_mockup.png)

---

### Python dungeon enemies — 2

#### Brass Prowler — 64×48

A low four-legged foundry automaton in blue-grey steel and warm brass. It has a teal visor slit, jointed brass legs, a pipe tail and a teal diamond crystal generator mounted on its back. The low, wide stance feels predatory and is unlike either Lua enemy.

- Palette: slate blue, blue highlight, brass, brass highlight, teal
- Contrast: brass and teal against slate-blue floors and walls
- Files: [`raw`](sprites/python_enemies/brass_prowler.png) · [`sheet`](previews/python_enemies.png) · [`room mockup`](previews/python_brass_prowler_mockup.png)

#### Cipher Warden — 64×64

A tall floating brass-and-basalt warden built around a large teal diamond core, with a ring halo, clamp arms, an obelisk lower body and a narrow visor mask. Its arrangement echoes Python's diamond motifs while keeping a distinct height and mechanical silhouette.

- Palette: dark slate, brass, brass highlight, teal, white
- Contrast: warm brass frame and bright teal core against the blue room
- Files: [`raw`](sprites/python_enemies/cipher_warden.png) · [`sheet`](previews/python_enemies.png) · [`room mockup`](previews/python_cipher_warden_mockup.png)

Combined room mockup: [`previews/python_enemies_mockup.png`](previews/python_enemies_mockup.png)

---

### Atmospheric birds — 2

#### Sunshard Finch — 24×24

A plump golden finch seen from above/three-quarter: coral-tipped wings, cream face, bright crest, dark eye and small rust tail. The two wing poses (with two bob positions each) are sliced into a four-frame flap loop used by the daytime ambient flocks.

- Palette: gold, cream, coral, rust, amber
- Read at gameplay size: small round golden body with two large wing shapes
- Files: [`raw`](sprites/birds/sunshard_finch.png) · [`sheet`](previews/birds.png) · [`scene mockup`](previews/birds_overworld_mockup.png)

#### Dusk Kite — 32×32

A larger indigo kite with swept wings, a pale throat, teal wing glints and a forked tail. Its dark silhouette is intended to read as a raptor against bright grass, with the teal pixels separating it from an ordinary crow.

- Palette: indigo, slate blue, teal, pale cyan, white
- Read at gameplay size: forked tail + angular wings
- Files: [`raw`](sprites/birds/dusk_kite.png) · [`sheet`](previews/birds.png) · [`scene mockup`](previews/birds_overworld_mockup.png)

---

### Will-o'-the-wisp — 1

#### Morrow Wisp — 32×32

An irregular teal flame with a pale-white heart and a dark empty eye mark, surrounded by a few detached spectral motes. The silhouette changes across four flame frames without becoming a torch, a generic particle or a smooth gradient.

- Palette: deep teal, mid-teal, bright cyan, pale white
- Preview files: [`primary`](sprites/wisp/morrow_wisp.png) · [`frames`](sprites/wisp/morrow_wisp_frames_4f.png) · [`concept sheet`](previews/wisp.png) · [`dark/light background review`](previews/wisp_backgrounds.png)

---

### Point-and-click cursors — 6 (applied)

The approved set is now applied at a native **24×24** in
`SandEEAlpha/sprites/ui/cursors/`. All six share:

- a dark 1 px silhouette
- an ivory pointer notch in the upper-left
- restrained, action-specific accent colours
- simple shapes that do not hide the target underneath

| Cursor | Visual language | Applied hotspot |
|---|---|---|
| Movement | teal comet-arrow, clearly directional; trailing glints | top-left |
| Open chest | small open chest with gold lid and spark | pointer notch |
| Open crafting | anvil + hammer, steel with a warm handle | pointer notch |
| Open furnace | brick furnace, chimney, arched fire mouth and grate | pointer notch |
| Open color crafter | painter's palette with four paint dots and brush | pointer notch |
| Generic interact | ivory gloved hand with teal spark | pointer notch |

\* Applied through `SandEEAlpha/scripts/cursor_manager.gd` at hotspot `(2,2)`. Cursors are desktop-only, change only over real world targets, and fall back to the OS arrow over UI. Android keeps touch-only input.

Preview: [`previews/cursors.png`](previews/cursors.png) — native and 6× nearest-neighbour on light overworld and dark UI backgrounds.

---

### Legendary items — exactly 5

All five are **32×32** inventory-icon concepts with transparent backgrounds, compact silhouettes, dark outlines and restrained rare-material highlights. They are intentionally not defined as game items.

1. **Starfall Prism** — *legendary artifact.* A tall, faceted sky-crystal in a thin gold crescent cradle, with pale blue and white facets, one violet facet and tiny star glints. Theme: a fallen piece of sky kept as a shrine relic.
2. **Rootbound Crown** — *legendary accessory.* A living circlet of dark roots, three moss-green leaves and a warm amber heart-gem. Theme: a forest crown that grew around its wearer rather than being forged.
3. **Eclipse Fang** — *legendary weapon.* A curved obsidian fang with a bone-white crescent guard, gold hilt and a single ember pommel. Theme: a blade cut from a moon-shadow.
4. **Tideglass Compass** — *legendary tool / relic.* A brass compass with a blue tideglass lens, coral-and-ivory needle and cardinal notches. Theme: a wayfinder for places that only exist at certain tides.
5. **Ashen Bell** — *legendary relic.* A blackened bronze bell with a teal rune band, ash cracks and an ember clapper. Theme: a funeral bell that remembers every name rung into it.

Raw icons: [`sprites/legendary_items/`](sprites/legendary_items/)  
Concept sheet: [`previews/legendary_items.png`](previews/legendary_items.png)  
Individual 8× checker previews: [`previews/isolated_large/`](previews/isolated_large/)

Name check: none of these five names appears in the current `SandEEAlpha/` resources or scripts. That is only a naming check; no item definitions were created.

---

## 4. Presentation files

### Category sheets

- [`previews/friendly_mobs.png`](previews/friendly_mobs.png)
- [`previews/overworld_enemies.png`](previews/overworld_enemies.png)
- [`previews/lua_enemies.png`](previews/lua_enemies.png)
- [`previews/python_enemies.png`](previews/python_enemies.png)
- [`previews/birds.png`](previews/birds.png)
- [`previews/wisp.png`](previews/wisp.png)
- [`previews/cursors.png`](previews/cursors.png)
- [`previews/legendary_items.png`](previews/legendary_items.png)

### Environment / context mockups

- Friendly mobs combined: [`previews/friendly_mobs_overworld_mockup.png`](previews/friendly_mobs_overworld_mockup.png)
- Mossback Nib alone: [`previews/friendly_mossback_nib_overworld_mockup.png`](previews/friendly_mossback_nib_overworld_mockup.png)
- Emberfox Kit alone: [`previews/friendly_emberfox_kit_overworld_mockup.png`](previews/friendly_emberfox_kit_overworld_mockup.png)
- Overworld enemies combined: [`previews/overworld_enemies_mockup.png`](previews/overworld_enemies_mockup.png)
- Cinder Ooze alone: [`previews/overworld_cinder_ooze_mockup.png`](previews/overworld_cinder_ooze_mockup.png)
- Gravebell Shambler alone: [`previews/overworld_gravebell_shambler_mockup.png`](previews/overworld_gravebell_shambler_mockup.png)
- Lua Rune Sentinel room: [`previews/lua_rune_sentinel_mockup.png`](previews/lua_rune_sentinel_mockup.png)
- Lua Vesper Acolyte room: [`previews/lua_vesper_acolyte_mockup.png`](previews/lua_vesper_acolyte_mockup.png)
- Lua combined room: [`previews/lua_enemies_mockup.png`](previews/lua_enemies_mockup.png)
- Python Brass Prowler room: [`previews/python_brass_prowler_mockup.png`](previews/python_brass_prowler_mockup.png)
- Python Cipher Warden room: [`previews/python_cipher_warden_mockup.png`](previews/python_cipher_warden_mockup.png)
- Python combined room: [`previews/python_enemies_mockup.png`](previews/python_enemies_mockup.png)
- Birds scene: [`previews/birds_overworld_mockup.png`](previews/birds_overworld_mockup.png)
- Wisp dark/light: [`previews/wisp_backgrounds.png`](previews/wisp_backgrounds.png)

### Included reference material

- [`reference/existing_style_inspection.png`](reference/existing_style_inspection.png) — actual project sprites, icons, waypoint and measurements
- [`reference/overworld_game_reference.png`](reference/overworld_game_reference.png) — actual overworld art capture used as mockup context
- [`reference/waypoint_reference.png`](reference/waypoint_reference.png) — 4× crop of the world waypoint sheet
- [`reference/asset_manifest.json`](reference/asset_manifest.json) — file sizes, dimensions and validation data

---

## 5. Format and implementation boundary

- Raw sprites are RGBA PNGs with transparent backgrounds.
- Animation strips are **concept sheets**, not Godot `SpriteFrames` resources. They are four frames left-to-right.
- No `.import` files were generated for the draft art.
- Dungeon room mockups reconstruct a representative 640×360 room from the existing Lua/Python tile textures and scale it 2× for review. They are not exports from a running dungeon.
- The overworld mockups use the captured title-panorama crop as a background and place 2× sprite previews with shadows and labels.
- Cursor concepts are now applied through `SandEEAlpha/scripts/cursor_manager.gd`; the draft folder itself still has no import files.
- The draft folder itself contains no runtime integration; the applied implementation lives under `SandEEAlpha/` and is recorded in `IMPLEMENTATION.md`.
- No production scene/resource references the draft files.

---

## 6. Reproduce / validate the draft

The generator is:

`design_drafts/sprite_concepts_2026/build_sprite_concepts.py`

It uses Pillow only, reads existing project tiles/textures for reference, and writes **only inside this draft directory**. To regenerate:

```powershell
python design_drafts/sprite_concepts_2026/build_sprite_concepts.py
```

Validation performed on the generated set:

- 11 character/bird/wisp concepts with transparent RGBA base sprites
- 4-frame horizontal idle/wing/flame strips
- 6 cursor sprites at 24×24
- exactly 5 legendary item icons at 32×32
- all preview/mockup files present
- no `.import` files in the draft tree
- no errors in [`reference/asset_manifest.json`](reference/asset_manifest.json)

The manifest is informational; it is not referenced by the game.

---

## 7. Implementation status

The eight creature concepts, the six cursor assets and both atmospheric birds have been approved and applied as production features. Their implementation is validated without a version bump, APK export, commit or push.

The remaining wisp and legendary-item concepts are reference drafts only: they are not imported into production, have no item definitions or loot rules, and are not referenced by runtime scenes.
