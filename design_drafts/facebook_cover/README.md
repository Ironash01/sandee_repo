# SandEE Facebook cover

Two ready-to-upload sizes:

| File | Size | Use |
|---|---:|---|
| `SandEE_facebook_cover_1640x624.png` | 1640 × 624 | High-resolution master |
| `SandEE_facebook_cover_820x312.png` | 820 × 312 | Facebook Page cover upload size |

## Design

- **Headline:** SANDEE
- **Tagline:** MINE. BUILD. CODE.
- **Descriptor:** An educational 2D open-world survival crafting game
- **Feature tags:** LUA + PYTHON / WINDOWS + ANDROID
- **Supporting line:** EXPLORE. AUTOMATE. LEARN.
- **Screenshot:** actual 0.9.5.1 PC gameplay, cropped to avoid the HUD corners
- **Tags/credit:** Lua + Python / Windows + Android, SandEE Developers, Alpha v0.9.5.1, placed below the screenshot

## Upload notes

- Upload the **1640 × 624** master; Facebook will downscale it to the Page cover slot.
- The Page profile picture overlaps the **bottom-left** of the cover. The bottom-left is intentionally clear; the brand block stays above it, and the tags/credit sit under the screenshot on the right.
- Keep the central/right screenshot visible when Facebook crops the sides on mobile.
- No call-to-action button is included in the image; use the Page's own button or a pinned post for that.
- Suggested Page tagline: **“Mine. Build. Code.”**

## Rebuild

Run:

```powershell
python design_drafts\facebook_cover\build_cover.py
```

The script uses the in-repo Ticketing/monogram fonts, the concept-C app icon, and the 0.9.5.1 PC screenshot from `docu_thesis/manual_draft/screenshots/pc_overworld.png`.
