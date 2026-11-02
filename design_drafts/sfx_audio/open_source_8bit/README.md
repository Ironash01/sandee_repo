# Open-source 8-bit SFX candidate list

**Status:** primary bank applied. The selected primary files now live in `SandEEAlpha/sfx/`, with `SFX` playback, the `SFX` bus, and gameplay hooks implemented. `sfx_hotbar` remains intentionally silent. This folder remains the provenance/audition record.

This folder maps the 90 cue families from `../sfx_inventory.csv` to free, open-licensed retro/8-bit sound packs.

## Recommended acquisition order

| Order | Pack | License | Why |
|---:|---|---|---|
| 1 | **Juhani Junkala 512** (`OGA512`) | CC0 | Broadest one-shot coverage: UI, impacts, weapons, explosions, movement, doors, portals, coins, death screams. |
| 2 | **Phoenix1291 8-bit Mini** (`PHX8`) | CC0 | Footsteps, roars, ouch, punches, pickups, powerups and teleports with 10 variants each. |
| 3 | **Little Robot 8-bit Library** (`LRSF8`) | CC-BY 3.0 | Clean jingles, craft, death, menu, open, pickup and shoot cues. Requires attribution. |
| 4 | **Lunar Lander 8-bit FX** (`LUNAR8`) | CC0 | Wind, water splash, rustle and debris; fills several one-shot gaps. |
| 5 | **30 CC0 SFX loops** (`LOOPS30`) | CC0 | Machine/noise/water loops for robots, weather and ambience beds. |
| 6 | **Loopable Dungeon Ambience** (`DUNGEON`) | CC0 | Ready cave/dungeon bed. |
| 7 | **Fireplace loop** (`FIRE`) | CC0 | Fire/campfire bed; trim and bitcrush. |

The first three packs are the 8-bit core. The last four are supplementary because the strict 8-bit packs have almost no ambience loops, fire, water or machine beds.

## Coverage

- **90 / 90** cue families mapped.
- `Direct` = usable after trim/volume; `Direct + pitch` = one-shots need pitch/EQ variants; `Layer` = mix two or more sources; `Layer + pitch` = mob recipes built by pitching/layering generic voices; `Process` = retro but not strict 8-bit, needs bitcrush/EQ; `Generate` = no suitable library sample, synthesize.

| Coverage | Cues |
|---|---:|
| Direct | 15 |
| Direct + pitch | 5 |
| Layer | 47 |
| Layer + pitch | 15 |
| Process | 7 |
| Generate | 1 |

| Category | Cues |
|---|---:|
| Player | 8 |
| Tools & World | 11 |
| Items & Interactables | 12 |
| UI & Progression | 13 |
| Crafting & Automation | 14 |
| Combat & Mobs | 19 |
| World & Dungeon | 13 |

- **P0 cue families:** 15. 8 are direct or direct+pitch; 7 need layering; 0 require generation from scratch.
- The full map references **232 distinct source files** (156 Juhani, 43 Phoenix, 17 Little Robot, 8 loops, 6 Lunar, 1 dungeon, 1 fire). The P0 subset needs only **65 distinct files**.

## What the packs do well

- **UI and feedback:** 14 button sounds, 10 menu moves/selects, 14 pause in/out, positive/negative/neutral sets.
- **Combat one-shots:** 95 explosions, 68 weapon sounds, 15 impacts, 32 death screams, 10 damage hits.
- **Movement:** 7 footsteps, 31 jump/land, 4 doors, 6 portals, 18 ladder/stairs.
- **8-bit character:** Phoenix gives 10 variants each for footsteps, roar, ouch, punch, pickup, powerup, teleport, explosion and menu.
- **Jingles:** Little Robot's win/lose/achievement jingles are a clean fit for mission/dungeon rewards.

## What is still missing or needs custom work

- **Creature identity.** The packs have generic roars, ouches and death screams, not 15 distinct mob voices. Each mob mapping is a recipe: pitch/formant-shift a base roar/ouch + a hit + a death scream. Expect to spend time auditioning; this is the largest manual gap.
- **Fire, cave and dungeon ambience.** Only the supplementary CC0 beds cover these, and they are not 8-bit. Bitcrush/low-pass them or synthesize noise loops.
- **Birds, chew/sip, bell, servo detail.** No direct samples. Generate short chirps/chews/bell tones with jsfxr or a noise generator, or record them.
- **Water and fishing.** Lunar Lander has a splash, but no bite/reel/line tick. Layer UI ticks and pitch-shifted splashes.
- **Material-specific impacts.** The packs give generic impacts; the material feel comes from EQ and layering, not from separate wood/stone/flesh libraries.

## License rules

- **CC0 packs** (`OGA512`, `PHX8`, `LUNAR8`, `LOOPS30`, `DUNGEON`, `FIRE`): no attribution required, commercial use allowed, modification allowed.
- **CC-BY 3.0 pack** (`LRSF8`): credit **Little Robot Sound Factory** and link **www.littlerobotsoundfactory.com**. Note any edits. See `ATTRIBUTION.md`.
- Keep this folder's `sources.csv` with the project so the provenance of every imported file is traceable.
- Do not import the paid 1000-sound SubspaceAudio pack; only the free 512-sound CC0 download is used here.

## Files

- `cue_source_map.csv` — one row per cue family: coverage, primary pack/files, secondary pack/files, processing and notes.
- `sources.csv` — pack-level source list with author, license, links, size and intended use.
- `ATTRIBUTION.md` — attribution text and license checklist.
- `fetch_and_stage.ps1` — downloads and extracts the packs into a local cache outside the repo.
- `audio/audition.html` — browser player grouped by cue, with priority/category filters.
- `audio/playlist.csv` — every cue/file pair with role, pack, and relative path.
- `audio/by_pack/` — 232 distinct audition clips (23.7 MB total).

## Suggested first pass

1. Open `audio/audition.html` and filter to **P0**.
2. Pick one or two variants per cue from the primary/secondary players.
3. Build a P0 bank of ~88-114 files: trim, normalize, pitch-variant, and name by cue ID.
4. Only then add the ambience/loop packs and custom-generated gaps.

The primary files are now imported into `SandEEAlpha/sfx/`; the copies under `audio/` remain audition references. Secondary fallback files have not been imported yet.
