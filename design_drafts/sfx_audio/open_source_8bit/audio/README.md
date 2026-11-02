# Audition copies

This folder contains **232 distinct source clips** copied from the packs listed in `../sources.csv`.
They are here only so the SFX can be auditioned; none of them are imported into `SandEEAlpha/`.

## Listen

Open `audition.html` in a browser. It groups every clip by cue family and lets you filter by priority/category.

- `primary` = first choice from `../cue_source_map.csv`
- `secondary` = fallback or layer source

`playlist.csv` lists every cue/file pair with its source pack and relative path.

## Layout

```
audio/
  audition.html
  playlist.csv
  by_pack/
    OGA512/...
    PHX8/...
    LRSF8/...
    LUNAR8/...
    LOOPS30/...
    DUNGEON/...
    FIRE/...
```

Files under `by_pack/` keep their original pack-relative paths, so they can be traced back to `sources.csv`.

## License

See `../ATTRIBUTION.md`. The Little Robot Sound Factory files are CC-BY 3.0 and require credit if shipped. All other packs used here are CC0.

## Note

These are the original pack files, not normalized or trimmed game assets. Import will handle trimming, normalization, and loop points.
