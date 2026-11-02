# SandEE SFX bank

Generated from `design_drafts/sfx_audio/open_source_8bit/cue_source_map.csv`.
Only the **primary** source files were imported; `sfx_hotbar` is intentionally
absent because hotbar selection stays silent.

- `sfx_manifest.json` — cue id → files, loop/spatial flags, mix defaults.
- `<cue_id>/` — the primary one-shot/loop files for that cue.

## Licensing

Most files are CC0. The Little Robot Sound Factory files are **CC-BY 3.0** and
require attribution if the game is distributed:

> "8-Bit Sound Effects Library" by Little Robot Sound Factory, licensed under CC BY 3.0.
> Source: https://opengameart.org/content/8-bit-sound-effects-library
> Changes: trimmed, pitch-shifted, equalized, and mixed for SandEE.

See `design_drafts/sfx_audio/open_source_8bit/ATTRIBUTION.md` for the full
checklist and `sources.csv` for pack-level provenance.

## Playback

`scripts/sfx_manager.gd` (autoload `SFX`) lazily loads these streams and routes
them to the `SFX` bus. All WAV sources were normalized to 16-bit PCM 44.1 kHz;
the fire ambience was converted to OGG to keep the bank small.
