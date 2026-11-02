# SandEE Documentation Notes

This file records the scope, conventions and maintenance notes for the SandEE documentation set. It is intended for the developers and technical writers who maintain the manual. It is not part of the player-facing guide.

## 1. Documentation Scope

The documentation covers the Windows and Android editions of SandEE and the systems that players use:

- Startup, account access and world management.
- The gameplay HUD, inventory, hotbar and map.
- Windows keyboard and mouse controls.
- Android touch controls and layout differences.
- Overworld gathering, building, farming, fishing, combat and waypoints.
- Crafting stations, furnaces, chests and the Color Crafter.
- Dungeons, Knowledge Altars, Quiz Altars, rewards and results.
- Regular caves and Pixie Caves.
- Automatica and its Lua functions.
- Algorithmica and its Python subset.
- Settings, help, troubleshooting and reference tables.

The manual describes the current public release. Development builds can differ.

## 2. Voice and Terminology

The manual is written as official SandEE documentation. It addresses players directly and describes features as product behaviour. It explains how the game works and what players can do, not how the documentation files were prepared.

Preferred terms:

- "SandEE provides..." or "The game supports..."
- "Players can..." or "To open..."
- "This section explains..." or "The following table lists..."
- "Not available" or "Not supported" for missing features.

Avoid phrasing that describes the documentation process rather than the game itself. Keep the focus on player actions, interface behaviour, technical requirements and limitations.

## 3. Formatting

The primary manual uses the page size required by the capstone template, Times New Roman 12 for body text and tables, 1.5 line spacing, justified body paragraphs and numbered chapter headings. The table of contents, list of figures and list of tables use Times New Roman 12 with page references and no dot leaders. The manual has no running header or footer so it can follow the capstone paper's own header and footer when merged.

Code blocks use a monospaced font. Inline code in prose is set in Times New Roman 12 italic so the body remains consistent with the typography requirement.

## 4. Screenshots

Screenshots are stored in `manual_assets/screenshots/` and organised by chapter. Figure numbers are sequential within each chapter and appear in the List of Figures. Captions describe the interface or action shown.

Android screenshots show the mobile layout, including the joystick, action buttons and the eight-slot hotbar with INV. Device-specific cutouts, gesture navigation and keyboard placement can vary.

Some account screens are not shown because they require an active online account. The sign-in, registration and offline-access flows are still explained in Chapter 4.

## 5. Known Product Limitations

The documentation should continue to state these limitations clearly:

- SandEE uses username-and-password authentication. Email registration, Google sign-in and password recovery are not available.
- Cloud saves, leaderboards and account switching require an online session. New worlds must be created online.
- Algorithmica accepts a restricted Python subset. Chained comparisons, `else`, `elif`, `def`, imports, f-strings and list comprehensions are not supported. `str`, `round` and `sum` are not available.
- Audio volumes and camera zoom are applied at runtime but are not stored in the settings files; they return to defaults on the next launch.
- The inventory does not provide right-click stack splitting.
- Later missions reuse the shared altar, quiz and results components. Individual walkthroughs for every mission are not included.
- Physical Android cutouts, gesture navigation and keyboard geometry can differ from the screenshots.

## 6. Project Areas

The player manual no longer documents the internal project structure. The repository contains 176 GDScript files, 49 scenes and 242 resource files. The documentation uses the same names for systems that appear in the in-game Help panel and the Programming Encyclopedia.

## 7. Documentation Files

| File | Purpose |
| --- | --- |
| `SandEE_User_Manual_Draft.docx` | Primary thesis-formatted manual. |
| `SandEE_User_Manual_Draft.md` | Editable Markdown source. |
| `manual_controls_windows.md` | Standalone Windows control reference. |
| `manual_controls_android.md` | Standalone Android control reference. |
| `manual_programming_reference.md` | Standalone Lua and Python reference. |
| `manual_interaction_inventory.md` | Standalone interaction inventory. |
| `manual_assets/screenshots/` | Screenshot files. |
| `build_manual.py` | DOCX/Markdown builder. |
| `collect_pages.py` | Page-reference collector for the TOC and lists. |
| `refresh_front_matter.py` | Refreshes the DOCX front matter and renumbers chapters after Word edits. |

## 8. Build Notes

`build_manual.py` reads `SandEE_User_Manual_Draft.md`, resolves figure and table references, and writes the DOCX. `collect_pages.py` reads the exported PDF and supplies page numbers for the table of contents and lists.

The two-pass build is intentional: the first pass fixes the layout, the page collector reads the PDF, and the second pass writes the page references. Run the collector again after any content change.

The DOCX is also edited directly in Word for layout changes and section moves. Those edits are not written back to the Markdown source. After a Word editing session, run `refresh_front_matter.py` to update the Table of Contents, List of Figures and List of Tables:

```
python docs/refresh_front_matter.py --pages-only
```

The script exports the DOCX with Word, matches every heading and caption to its page, and rewrites the three lists. It repeats the export until the page numbers stop moving. Pass `--shift N` only when the chapter numbering itself has to change; it subtracts N from every chapter, section, figure and table number and from every reference to one.

Because page numbers come from Word, the exported PDF matches the pagination that readers see in Word. Do not use the Markdown build to update a Word-edited DOCX; it would discard the layout changes.

## 9. Maintenance Notes

When adding a section:

1. Add the heading to the Markdown source.
2. Add figures near the instructions they support.
3. Assign a unique `{#fig:...}` identifier and reference it with `{{fig:...}}`.
4. Add a table caption with a unique `{#tab:...}` identifier.
5. Rebuild the DOCX and PDF.
6. Check the List of Figures and List of Tables.

When removing a feature, update the manual, the control references, the programming reference and the interaction inventory together. Do not leave a control or function documented if it is no longer available.
