from pathlib import Path
from docx import Document
from docx.shared import Pt, Inches, RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH, WD_LINE_SPACING
from docx.enum.table import WD_TABLE_ALIGNMENT
from docx.enum.style import WD_STYLE_TYPE
from docx.enum.section import WD_SECTION
from docx.oxml import OxmlElement
from docx.oxml.ns import qn

ROOT = Path(r"C:\Users\Krosis\Documents\github_repos\sandee_repo")
OUT = ROOT / "docu_thesis" / "manual_draft"
SHOTS = OUT / "screenshots"
DOCX = OUT / "SandEE_User_Manual_Draft.docx"
PDF = OUT / "SandEE_User_Manual_Draft.pdf"

# ── Base document ──────────────────────────────────────────────────
doc = Document()
doc.core_properties.title = "SandEE User Manual (Draft)"
doc.core_properties.subject = "Windows PC and Android user manual"
doc.core_properties.author = "SandEE Developers"
doc.core_properties.keywords = "SandEE, user manual, PC, Android, Lua, Python, game"
doc.core_properties.comments = "Draft for review. Screenshots from build 0.9.4.8."

sec = doc.sections[0]
sec.page_width = Inches(8.5)
sec.page_height = Inches(11)
sec.left_margin = Inches(1.5)
sec.right_margin = Inches(1.0)
sec.top_margin = Inches(1.0)
sec.bottom_margin = Inches(1.0)
sec.header_distance = Inches(0.5)
sec.footer_distance = Inches(0.5)


def set_run_font(run, name="Times New Roman", size=12, bold=None, italic=None, color=None):
    run.font.name = name
    run._element.rPr.rFonts.set(qn("w:eastAsia"), name)
    run.font.size = Pt(size)
    if bold is not None:
        run.bold = bold
    if italic is not None:
        run.italic = italic
    if color is not None:
        run.font.color.rgb = color


def style_font(style, name="Times New Roman", size=12, bold=None, italic=None):
    style.font.name = name
    r_fonts = style.element.get_or_add_rPr().rFonts
    for attr in ("asciiTheme", "hAnsiTheme", "eastAsiaTheme", "cstheme"):
        if r_fonts.get(qn("w:" + attr)) is not None:
            del r_fonts.attrib[qn("w:" + attr)]
    for attr in ("ascii", "hAnsi", "eastAsia", "cs"):
        r_fonts.set(qn("w:" + attr), name)
    style.font.size = Pt(size)
    if bold is not None:
        style.font.bold = bold
    if italic is not None:
        style.font.italic = italic
    style.font.color.rgb = RGBColor(0, 0, 0)


# Normal is deliberately plain; Body adds the thesis first-line indent.
normal = doc.styles["Normal"]
style_font(normal, size=12)
normal.paragraph_format.line_spacing = 1.5
normal.paragraph_format.space_before = Pt(0)
normal.paragraph_format.space_after = Pt(0)
normal.paragraph_format.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
normal.paragraph_format.first_line_indent = Inches(0)

body = doc.styles.add_style("Manual Body", WD_STYLE_TYPE.PARAGRAPH)
body.base_style = normal
style_font(body, size=12)
body.paragraph_format.line_spacing = 1.5
body.paragraph_format.space_before = Pt(0)
body.paragraph_format.space_after = Pt(0)
body.paragraph_format.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
body.paragraph_format.first_line_indent = Inches(0.5)
body.paragraph_format.widow_control = True

bullet = doc.styles.add_style("Manual Bullet", WD_STYLE_TYPE.PARAGRAPH)
bullet.base_style = doc.styles["List Bullet"]
style_font(bullet, size=12)
bullet.paragraph_format.line_spacing = 1.5
bullet.paragraph_format.space_before = Pt(0)
bullet.paragraph_format.space_after = Pt(3)
bullet.paragraph_format.left_indent = Inches(0.5)
bullet.paragraph_format.first_line_indent = Inches(-0.25)

step = doc.styles.add_style("Manual Step", WD_STYLE_TYPE.PARAGRAPH)
step.base_style = normal
style_font(step, size=12)
step.paragraph_format.line_spacing = 1.5
step.paragraph_format.space_before = Pt(0)
step.paragraph_format.space_after = Pt(3)
step.paragraph_format.alignment = WD_ALIGN_PARAGRAPH.LEFT
step.paragraph_format.left_indent = Inches(0.55)
step.paragraph_format.first_line_indent = Inches(-0.3)

note = doc.styles.add_style("Manual Note", WD_STYLE_TYPE.PARAGRAPH)
note.base_style = normal
style_font(note, size=11, italic=True)
note.paragraph_format.line_spacing = 1.15
note.paragraph_format.space_before = Pt(4)
note.paragraph_format.space_after = Pt(6)
note.paragraph_format.alignment = WD_ALIGN_PARAGRAPH.LEFT
note.paragraph_format.left_indent = Inches(0.35)

caption = doc.styles.add_style("Manual Caption", WD_STYLE_TYPE.PARAGRAPH)
caption.base_style = normal
style_font(caption, size=10)
caption.paragraph_format.line_spacing = 1.0
caption.paragraph_format.space_before = Pt(3)
caption.paragraph_format.space_after = Pt(8)
caption.paragraph_format.alignment = WD_ALIGN_PARAGRAPH.CENTER
caption.paragraph_format.first_line_indent = Inches(0)
caption.paragraph_format.keep_together = True

table_caption = doc.styles.add_style("Manual Table Caption", WD_STYLE_TYPE.PARAGRAPH)
table_caption.base_style = normal
style_font(table_caption, size=10)
table_caption.paragraph_format.line_spacing = 1.0
table_caption.paragraph_format.space_before = Pt(8)
table_caption.paragraph_format.space_after = Pt(4)
table_caption.paragraph_format.alignment = WD_ALIGN_PARAGRAPH.LEFT
table_caption.paragraph_format.first_line_indent = Inches(0)
table_caption.paragraph_format.keep_with_next = True

table_text = doc.styles.add_style("Manual Table Text", WD_STYLE_TYPE.PARAGRAPH)
table_text.base_style = normal
style_font(table_text, size=10)
table_text.paragraph_format.line_spacing = 1.0
table_text.paragraph_format.space_before = Pt(0)
table_text.paragraph_format.space_after = Pt(1)
table_text.paragraph_format.alignment = WD_ALIGN_PARAGRAPH.LEFT
table_text.paragraph_format.first_line_indent = Inches(0)

code_style = doc.styles.add_style("Manual Code", WD_STYLE_TYPE.PARAGRAPH)
code_style.base_style = normal
style_font(code_style, name="Consolas", size=9)
code_style.paragraph_format.line_spacing = 1.0
code_style.paragraph_format.space_before = Pt(0)
code_style.paragraph_format.space_after = Pt(0)
code_style.paragraph_format.alignment = WD_ALIGN_PARAGRAPH.LEFT
code_style.paragraph_format.first_line_indent = Inches(0)

figure_title = doc.styles.add_style("Manual Figure Title", WD_STYLE_TYPE.PARAGRAPH)
figure_title.base_style = normal
style_font(figure_title, size=11, bold=True)
figure_title.paragraph_format.line_spacing = 1.0
figure_title.paragraph_format.space_before = Pt(0)
figure_title.paragraph_format.space_after = Pt(8)
figure_title.paragraph_format.alignment = WD_ALIGN_PARAGRAPH.LEFT
figure_title.paragraph_format.first_line_indent = Inches(0)

front_heading = doc.styles.add_style("Manual Front Heading", WD_STYLE_TYPE.PARAGRAPH)
front_heading.base_style = normal
style_font(front_heading, size=13, bold=True)
front_heading.paragraph_format.line_spacing = 1.0
front_heading.paragraph_format.space_before = Pt(0)
front_heading.paragraph_format.space_after = Pt(12)
front_heading.paragraph_format.alignment = WD_ALIGN_PARAGRAPH.CENTER
front_heading.paragraph_format.first_line_indent = Inches(0)

# Built-in headings drive the TOC. Keep them black, Times, and thesis-sized.
h1 = doc.styles["Heading 1"]
style_font(h1, size=14, bold=True)
h1.font.color.rgb = RGBColor(0, 0, 0)
h1.paragraph_format.line_spacing = 1.0
h1.paragraph_format.space_before = Pt(0)
h1.paragraph_format.space_after = Pt(14)
h1.paragraph_format.alignment = WD_ALIGN_PARAGRAPH.CENTER
h1.paragraph_format.first_line_indent = Inches(0)
h1.paragraph_format.keep_with_next = True

h2 = doc.styles["Heading 2"]
style_font(h2, size=12, bold=True)
h2.font.color.rgb = RGBColor(0, 0, 0)
h2.paragraph_format.line_spacing = 1.5
h2.paragraph_format.space_before = Pt(12)
h2.paragraph_format.space_after = Pt(4)
h2.paragraph_format.alignment = WD_ALIGN_PARAGRAPH.LEFT
h2.paragraph_format.first_line_indent = Inches(0)
h2.paragraph_format.keep_with_next = True

h3 = doc.styles["Heading 3"]
style_font(h3, size=12, bold=True, italic=True)
h3.font.color.rgb = RGBColor(0, 0, 0)
h3.paragraph_format.line_spacing = 1.5
h3.paragraph_format.space_before = Pt(8)
h3.paragraph_format.space_after = Pt(2)
h3.paragraph_format.alignment = WD_ALIGN_PARAGRAPH.LEFT
h3.paragraph_format.first_line_indent = Inches(0)
h3.paragraph_format.keep_with_next = True


# ── Fields, numbering, tables, figures ─────────────────────────────
def add_field(paragraph, instruction, placeholder="1"):
    run = paragraph.add_run()
    fld_begin = OxmlElement("w:fldChar")
    fld_begin.set(qn("w:fldCharType"), "begin")
    instr = OxmlElement("w:instrText")
    instr.set(qn("xml:space"), "preserve")
    instr.text = instruction
    fld_sep = OxmlElement("w:fldChar")
    fld_sep.set(qn("w:fldCharType"), "separate")
    text = OxmlElement("w:t")
    text.text = placeholder
    fld_end = OxmlElement("w:fldChar")
    fld_end.set(qn("w:fldCharType"), "end")
    run._r.append(fld_begin)
    run._r.append(instr)
    run._r.append(fld_sep)
    run._r.append(text)
    run._r.append(fld_end)


def add_page_field(paragraph):
    fld = OxmlElement("w:fldSimple")
    fld.set(qn("w:instr"), "PAGE")
    run = OxmlElement("w:r")
    text = OxmlElement("w:t")
    text.text = "1"
    run.append(text)
    fld.append(run)
    paragraph._p.append(fld)


def set_page_number_format(section, fmt, start):
    sect_pr = section._sectPr
    pg = sect_pr.find(qn("w:pgNumType"))
    if pg is None:
        pg = OxmlElement("w:pgNumType")
        cols = sect_pr.find(qn("w:cols"))
        if cols is not None:
            cols.addprevious(pg)
        else:
            sect_pr.append(pg)
    pg.set(qn("w:fmt"), fmt)
    pg.set(qn("w:start"), str(start))


def prevent_row_split(row):
    tr_pr = row._tr.get_or_add_trPr()
    cant_split = OxmlElement("w:cantSplit")
    tr_pr.append(cant_split)


def style_cell(cell, text, bold=False, size=10, align=WD_ALIGN_PARAGRAPH.LEFT):
    cell.text = ""
    p = cell.paragraphs[0]
    p.style = doc.styles["Manual Table Text"]
    p.alignment = align
    run = p.add_run(str(text))
    set_run_font(run, size=size, bold=bold)
    tc_pr = cell._tc.get_or_add_tcPr()
    tc_mar = OxmlElement("w:tcMar")
    for side, value in (("top", 40), ("bottom", 40), ("left", 70), ("right", 70)):
        el = OxmlElement(f"w:{side}")
        el.set(qn("w:w"), str(value))
        el.set(qn("w:type"), "dxa")
        tc_mar.append(el)
    tc_pr.append(tc_mar)


def shade_cell(cell, fill):
    tc_pr = cell._tc.get_or_add_tcPr()
    shd = OxmlElement("w:shd")
    shd.set(qn("w:fill"), fill)
    tc_pr.append(shd)


def add_table(headers, rows, widths, caption_text, numbered=True):
    p = doc.add_paragraph(style="Manual Table Caption")
    if numbered:
        p.add_run("Table ")
        add_field(p, " SEQ Table \\* ARABIC ")
        p.add_run(". " + caption_text)
    else:
        p.add_run(caption_text)
    table = doc.add_table(rows=1, cols=len(headers))
    table.style = "Table Grid"
    table.alignment = WD_TABLE_ALIGNMENT.CENTER
    table.autofit = False
    for i, header in enumerate(headers):
        cell = table.rows[0].cells[i]
        style_cell(cell, header, bold=True)
        shade_cell(cell, "D9E2F3")
        cell.width = Inches(widths[i])
    prevent_row_split(table.rows[0])
    tr_pr = table.rows[0]._tr.get_or_add_trPr()
    tbl_header = OxmlElement("w:tblHeader")
    tbl_header.set(qn("w:val"), "true")
    tr_pr.append(tbl_header)
    for row in rows:
        new_row = table.add_row()
        prevent_row_split(new_row)
        cells = new_row.cells
        for i, value in enumerate(row):
            style_cell(cells[i], value)
            cells[i].width = Inches(widths[i])
    doc.add_paragraph(style="Manual Note").add_run(" ").font.size = Pt(2)
    return table


def add_code_block(code):
    table = doc.add_table(rows=1, cols=1)
    table.style = "Table Grid"
    table.alignment = WD_TABLE_ALIGNMENT.CENTER
    cell = table.cell(0, 0)
    cell.text = ""
    shade_cell(cell, "F2F2F2")
    tc_pr = cell._tc.get_or_add_tcPr()
    tc_mar = OxmlElement("w:tcMar")
    for side, value in (("top", 80), ("bottom", 80), ("left", 100), ("right", 100)):
        el = OxmlElement(f"w:{side}")
        el.set(qn("w:w"), str(value))
        el.set(qn("w:type"), "dxa")
        tc_mar.append(el)
    tc_pr.append(tc_mar)
    p = cell.paragraphs[0]
    p.style = doc.styles["Manual Code"]
    p.add_run(code)
    doc.add_paragraph(style="Manual Note").add_run(" ").font.size = Pt(2)


def add_caption(text):
    p = doc.add_paragraph(style="Manual Caption")
    p.add_run("Figure ")
    add_field(p, " SEQ Figure \\* ARABIC ")
    p.add_run(". " + text)


def add_figure(path, text, width=5.7):
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p.paragraph_format.space_before = Pt(2)
    p.paragraph_format.space_after = Pt(0)
    p.paragraph_format.first_line_indent = Inches(0)
    p.paragraph_format.keep_with_next = True
    p.add_run().add_picture(str(path), width=Inches(width))
    add_caption(text)


def figure_page(title, items):
    doc.add_page_break()
    p = doc.add_paragraph(style="Manual Figure Title")
    p.add_run(title)
    for path, text in items:
        add_figure(path, text)


def h1_chapter(text, first=False):
    if not first:
        doc.add_page_break()
    doc.add_paragraph(text, style="Heading 1")


def h2_section(text):
    doc.add_paragraph(text, style="Heading 2")


def h3_section(text):
    doc.add_paragraph(text, style="Heading 3")


def para(text):
    doc.add_paragraph(text, style="Manual Body")


def bullet_item(text):
    doc.add_paragraph(text, style="Manual Bullet")


def bullet_rich(parts):
    p = doc.add_paragraph(style="Manual Bullet")
    for text, bold, monospace in parts:
        r = p.add_run(text)
        set_run_font(r, name="Consolas" if monospace else "Times New Roman",
                     size=11 if monospace else 12, bold=bold)
    return p


def step_item(text):
    doc.add_paragraph(text, style="Manual Step")


def note_item(text):
    doc.add_paragraph(text, style="Manual Note")


def front_title(text):
    doc.add_paragraph(text, style="Manual Front Heading")


# ── Title page ─────────────────────────────────────────────────────
for _ in range(4):
    doc.add_paragraph()
p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.CENTER
r = p.add_run("SANDEE")
set_run_font(r, size=34, bold=True)
p.paragraph_format.space_after = Pt(6)
p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.CENTER
r = p.add_run("An Educational Multi-Platform 2D Open World\nSurvival Crafting Game for Lua and Python")
set_run_font(r, size=14, bold=False)
p.paragraph_format.space_after = Pt(26)
p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.CENTER
r = p.add_run("USER MANUAL")
set_run_font(r, size=21, bold=True)
p.paragraph_format.space_after = Pt(4)
p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.CENTER
r = p.add_run("Windows PC and Android")
set_run_font(r, size=12)
p.paragraph_format.space_after = Pt(2)
p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.CENTER
r = p.add_run("Version 0.9.4.8")
set_run_font(r, size=12)
p.paragraph_format.space_after = Pt(2)
p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.CENTER
r = p.add_run("Draft for Review")
set_run_font(r, size=12, italic=True)
p.paragraph_format.space_after = Pt(70)
for text in ("SandEE Developers", "October 2026"):
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    r = p.add_run(text)
    set_run_font(r, size=12)
    p.paragraph_format.space_after = Pt(2)

# ── Front matter section ───────────────────────────────────────────
front = doc.add_section(WD_SECTION.NEW_PAGE)
front.page_width = Inches(8.5)
front.page_height = Inches(11)
front.left_margin = Inches(1.5)
front.right_margin = Inches(1.0)
front.top_margin = Inches(1.0)
front.bottom_margin = Inches(1.0)
front.header_distance = Inches(0.5)
front.footer_distance = Inches(0.5)
set_page_number_format(front, "lowerRoman", 1)
front.footer.is_linked_to_previous = False
fp = front.footer.paragraphs[0]
fp.alignment = WD_ALIGN_PARAGRAPH.CENTER
add_page_field(fp)
front.header.is_linked_to_previous = False
front.header.paragraphs[0].text = ""

front_title("DOCUMENT CONTROL")
para("This document is a draft user manual for the Windows PC and Android builds of SandEE. It describes the player-facing interface, controls, systems, and common procedures. It does not document the Godot editor, the server backend, or internal development tools. Screenshots were captured from the 0.9.4.8 development build; final release screenshots should be recaptured after the interface freeze.")
add_table(
    ["Item", "Details"],
    [
        ("Document title", "SandEE User Manual"),
        ("Document type", "Player manual (draft)"),
        ("Game version", "0.9.4.8"),
        ("Platforms", "Windows PC (64-bit) and Android (arm64-v8a)"),
        ("Audience", "Players, evaluators, and thesis reviewers"),
        ("Prepared by", "SandEE Developers"),
        ("Date", "October 2026"),
        ("Status", "Draft for review; not a final release manual"),
    ],
    [1.6, 4.4],
    "Document control information.",
    numbered=False,
)

front_title("REVISION HISTORY")
add_table(
    ["Version", "Date", "Description", "Author"],
    [("0.1", "October 2026", "Initial manual draft for PC and Android.", "SandEE Developers")],
    [0.8, 1.2, 3.2, 1.8],
    "Revision history.",
    numbered=False,
)

front_title("MANUAL CONVENTIONS")
para("The following conventions are used throughout the manual:")
bullet_rich([
    ("Bold text such as ", False, False), ("Resume", True, False),
    (", ", False, False), ("Settings", True, False), (", or ", False, False),
    ("BUILD", True, False),
    (" identifies a button, menu entry, or other interface label.", False, False),
])
bullet_rich([
    ("Monospaced text such as ", False, False), ("set_recipe()", False, True),
    (", ", False, False), ("craft()", False, True), (", or ", False, False),
    ("craft_color()", False, True),
    (" identifies code, a function name, or a scripting item identifier.", False, False),
])
bullet_item("Click means a mouse click on the PC build. Tap means a touch on the Android build. Drag means press and move while holding the primary mouse button or a finger.")
bullet_item("LMB means the left mouse button. Shift + click means hold Shift while clicking.")
bullet_item("A note in italic text marks a warning, limitation, or point that differs between platforms.")
note_item("SandEE is a development build. Menus, balance values, and screenshots may change before release. The in-game Help & Documentation panel remains the authoritative quick reference for the current build.")

doc.add_page_break()
front_title("TABLE OF CONTENTS")
p = doc.add_paragraph()
p.paragraph_format.first_line_indent = Inches(0)
add_field(p, ' TOC \\o "1-2" \\h \\z \\u ', "Right-click and choose Update Field to build the table of contents.")
p = doc.add_paragraph(style="Manual Note")
p.add_run("The table of contents is a Word field. It updates automatically when the document is opened with field updating enabled, or manually through References > Update Table.")

doc.add_page_break()
front_title("LIST OF FIGURES")
p = doc.add_paragraph()
p.paragraph_format.first_line_indent = Inches(0)
add_field(p, ' TOC \\h \\z \\c "Figure" ', "Right-click and choose Update Field to build the list of figures.")
p = doc.add_paragraph(style="Manual Note")
p.add_run("All screenshots are from the SandEE 0.9.4.8 development build. PC and Android screenshots were captured at 1920 x 1080.")

doc.add_page_break()
front_title("LIST OF TABLES")
p = doc.add_paragraph()
p.paragraph_format.first_line_indent = Inches(0)
add_field(p, ' TOC \\h \\z \\c "Table" ', "Right-click and choose Update Field to build the list of tables.")

# ── Body section ───────────────────────────────────────────────────
body_sec = doc.add_section(WD_SECTION.NEW_PAGE)
body_sec.page_width = Inches(8.5)
body_sec.page_height = Inches(11)
body_sec.left_margin = Inches(1.5)
body_sec.right_margin = Inches(1.0)
body_sec.top_margin = Inches(1.0)
body_sec.bottom_margin = Inches(1.0)
body_sec.header_distance = Inches(0.5)
body_sec.footer_distance = Inches(0.5)
set_page_number_format(body_sec, "decimal", 1)
body_sec.footer.is_linked_to_previous = False
bp = body_sec.footer.paragraphs[0]
bp.alignment = WD_ALIGN_PARAGRAPH.CENTER
add_page_field(bp)
body_sec.header.is_linked_to_previous = False
hp = body_sec.header.paragraphs[0]
hp.alignment = WD_ALIGN_PARAGRAPH.RIGHT
hr = hp.add_run("SandEE User Manual  |  Draft 0.9.4.8")
set_run_font(hr, size=9, italic=True, color=RGBColor(80, 80, 80))
hp.paragraph_format.space_after = Pt(0)

# ── Chapter 1 ──────────────────────────────────────────────────────
h1_chapter("CHAPTER 1: INTRODUCTION", first=True)
h2_section("1.1 Purpose of the Manual")
para("This manual explains how to install, start, control, and operate SandEE on Windows PC and Android. It is written for first-time players, usability evaluators, and thesis reviewers who need a single reference for the game's interface and core systems. The manual follows the player's progression: installation, first launch, movement and survival, building and crafting, programming and automation, combat and dungeons, and finally saving and troubleshooting.")
para("The manual is intentionally descriptive rather than exhaustive. Recipes, item statistics, and mission lists change during development, so the in-game Help & Documentation panel and the Programming Encyclopedia should be treated as the current source of truth. This document focuses on procedures and on the reasoning behind the interface so that a reader can operate the game without guessing.")

h2_section("1.2 Game Overview")
para("SandEE is a 2D open-world survival crafting game with a programming-learning layer. The player explores a procedurally generated world, gathers resources, builds shelters and machines, fights hostile creatures, and clears language-themed dungeons. Two programming systems sit on top of the sandbox: Automatica, which uses Lua to control a robot helper, and Algorithmica, which uses Python to automate crafting stations and furnaces.")
para("The world contains plains and forest, desert, snowy terrain, water, caves, Pixie Caves, and dungeon entrances. The player has health and stamina but no hunger or thirst meter. Food is a healing item rather than a survival requirement. A full day/night cycle lasts 24 real minutes, with roughly 12 minutes of day and 12 minutes of night. Night increases the hostile population and changes which creatures appear.")
para("Progression is organized around missions and stars. The main mission flow introduces Automatica and Algorithmica through short guided objectives, then moves into dungeon tracks for Lua and Python. Clearing both language tracks unlocks the Hitman miniboss dungeon. Defeating the Hitman completes the main story, and clearing the main tracks plus any extra dungeons unlocks the side missions. A Bestiary records creatures that the player has seen and defeated.")

h2_section("1.3 Educational Goals")
para("The educational layer is not a separate quiz mode. Programming is embedded in the sandbox: a Lua program moves a robot that chops trees, mines blocks, builds structures, and deposits loot; a Python program selects recipes, feeds machines, smelts ore, and collects output. The player therefore sees the effect of code on the game world immediately.")
para("The Programming Encyclopedia provides function references and unlocks language concepts through dungeon Knowledge Altars. The first dungeon teaches the altar and quiz flow, while later dungeons add language-specific material. The intent is to move the player from guided examples to independent automation: first copy a template, then change item names and quantities, then combine calls into a useful production loop.")

h2_section("1.4 Supported Platforms")
para("This manual covers two builds:")
bullet_item("Windows PC: a 64-bit desktop build controlled with a keyboard and mouse.")
bullet_item("Android: a touch build controlled with a virtual joystick, on-screen buttons, and direct taps on the world.")
note_item("The current project exports Windows and Android only. iOS is not covered by this manual. The Android build is arm64-v8a; it is intended for modern 64-bit devices.")

h2_section("1.5 How to Use This Manual")
para("Readers who are new to the game should read Chapters 2 and 3 in order, then use Chapter 4 as a control reference while playing. Readers who only need a specific system can go directly to Chapter 5 for survival and gathering, Chapter 6 for building and crafting, Chapter 7 for programming, or Chapter 8 for combat and dungeons. Appendix A condenses the controls into two quick-reference tables, and Appendix B defines the terminology used throughout the manual.")

# ── Chapter 2 ──────────────────────────────────────────────────────
h1_chapter("CHAPTER 2: SYSTEM REQUIREMENTS AND INSTALLATION")
h2_section("2.1 Windows PC Requirements")
para("The Windows build is a 64-bit desktop application. The values in Table 1 are draft targets for the current development build; they should be rechecked against the final exported package. A machine that meets the minimum row can run the game at 1280 x 720 with reduced visual comfort. The recommended row is the configuration used for the screenshots in this manual.")
add_table(
    ["Component", "Minimum", "Recommended"],
    [
        ("Operating system", "Windows 10 64-bit", "Windows 11 64-bit"),
        ("Processor", "Dual-core, 2.0 GHz", "Quad-core, 2.5 GHz or better"),
        ("Memory", "4 GB RAM", "8 GB RAM"),
        ("Graphics", "DirectX 12 compatible, 2 GB VRAM", "Dedicated GPU, 4 GB VRAM"),
        ("Storage", "500 MB free", "1 GB free"),
        ("Display", "1280 x 720", "1920 x 1080"),
        ("Input", "Keyboard and mouse", "Keyboard and mouse"),
        ("Audio", "Stereo output", "Headphones or stereo speakers"),
    ],
    [1.35, 2.25, 2.4],
    "Draft Windows PC requirements.",
)

h2_section("2.2 Android Requirements")
para("The Android build targets 64-bit ARM devices. The game uses a landscape orientation and a responsive touch interface. Table 2 lists draft targets; low-memory devices may still run the game, but world generation and dungeon transitions will take longer.")
add_table(
    ["Component", "Minimum", "Recommended"],
    [
        ("Operating system", "Android 8.0 (API 26)", "Android 11 or newer"),
        ("Processor", "64-bit ARM, quad-core", "64-bit ARM, octa-core"),
        ("Memory", "2 GB RAM", "4 GB RAM or more"),
        ("Storage", "200 MB free", "500 MB free"),
        ("Display", "1280 x 720, landscape", "1920 x 1080, landscape"),
        ("Input", "Touchscreen", "Touchscreen, 4.7 inches or larger"),
        ("Other", "No camera, microphone, or location permission required", "Same"),
    ],
    [1.35, 2.35, 2.3],
    "Draft Android requirements.",
)

h2_section("2.3 Installing on Windows PC")
para("The PC build is distributed as a ZIP archive. The executable and its data files must remain together; running the executable from inside the ZIP viewer will fail.")
step_item("1. Download the SandEE Windows ZIP package for the current version.")
step_item("2. Right-click the ZIP file and choose Extract All, or use a trusted archive tool. Extract to a normal folder such as Documents\\SandEE.")
step_item("3. Open the extracted folder and run sandee.exe.")
step_item("4. If Windows SmartScreen appears, choose More info, confirm the publisher or source, and then choose Run anyway. Only bypass the warning for a build obtained from the official distribution link.")
step_item("5. On first launch, sign in with an account or choose Play Offline. Offline play requires a previously verified local account on that device.")
step_item("6. From the main menu, choose Worlds, then create a new world or open an existing one.")
note_item("Do not move only the executable. The .pck data file and the accompanying DLLs must stay in the same folder. If the game reports a missing extension or a blank window, re-extract the complete ZIP rather than copying individual files.")

h2_section("2.4 Installing on Android")
para("The Android build is distributed as an APK. Because the APK is installed outside a store, Android will ask the player to allow installation from the app that opens the file.")
step_item("1. Download or transfer the SandEE APK to the device.")
step_item("2. Open the APK from the Files app or the browser's download notification.")
step_item("3. If prompted, allow the current app to install unknown apps. This is a per-app permission; it can be revoked after installation.")
step_item("4. Tap Install, then Open.")
step_item("5. On first launch, sign in or choose Play Offline, then create or open a world.")
note_item("Updating: install the new APK over the existing app to keep local saves. Uninstalling the app removes its local app data. Use cloud saves before uninstalling or changing devices.")

h2_section("2.5 First Launch, Accounts, and Offline Mode")
para("SandEE uses an account layer for cloud saves and leaderboards. A new world requires an online session. Existing worlds that belong to the currently verified account can be opened through Play Offline. The offline path does not list another account's worlds and does not create new worlds.")
para("If the account state is interrupted, the game blocks world access until verification completes. This is deliberate: it prevents one account's local world from being opened under another account. When the connection returns, the cloud sync compares save revisions. If two devices share the same world identifier, the newer revision wins. A different world in the same slot is treated as a protected conflict and is not overwritten automatically; use Cloud Saves to download a copy or resolve the slot.")
note_item("A first-time player who wants to evaluate the game without creating an account should use the offline path only after a verified account has been established on that device. The account gate is part of the current build, not an optional tutorial step.")

h2_section("2.6 Uninstalling and Backing Up")
para("On Windows, the game stores its user data outside the extracted folder. Removing the game folder does not necessarily remove saves. Before deleting user data, open the Worlds screen and confirm which worlds are backed up to the account. On Android, uninstalling removes app-private local data; cloud saves are the reliable transfer path. The game writes saves atomically and keeps a .bak safety copy, but a backup copy is not a substitute for a cloud save.")

# ── Chapter 3 ──────────────────────────────────────────────────────
h1_chapter("CHAPTER 3: GETTING STARTED")
h2_section("3.1 Creating or Opening a World")
para("After sign-in or offline verification, the main menu opens the Worlds screen. A world is a save slot with its own seed, terrain edits, placed blocks, containers, machines, missions, tutorial progress, dungeon state, Bestiary, and knowledge entries. Creating a world generates the terrain from a seed and starts the opening tutorial. Opening an existing world restores its saved state, including the player's position and the state of placed machines.")
para("The world list supports create, load, rename, and delete. Deletion is permanent for that device and should be treated as a destructive action. The game asks for confirmation before deleting a world.")

h2_section("3.2 The Opening Tutorial")
para("New worlds begin in a guided camp. The tutorial is intentionally short and action-based: it shows one objective at a time, marks the exact target, and waits for the player to perform the action. The starter kit contains the Wooden Axe, Wooden Pickaxe, Wooden Sword, and 10 Bread. The kit is granted once per new world. Tutorial camp structures such as the furnace are protected from mining and dismantling until onboarding finishes, so they cannot be accidentally removed and rebuilt mid-lesson.")
para("The opening sequence introduces movement, hotbar selection, tree chopping, item pickup, and the Crafting Station. It then leads the player to the first dungeon entrance. Inside the dungeon, the player learns the Knowledge Altar, route markers, and the Quiz Altar. After the dungeon, the camp teaches Automatica, Algorithmica, regular caves, Pixie Caves, and Skyglass Waypoints. The first Pixie Cave is a safe introduction with no pixies; later Pixie Caves are guarded.")
para("The objective card appears at the top-centre of the screen. Tutorial targets have a pulsing marker and a compass arrow above the player. A SKIP LESSON button is available while dialogue is active; the objective card can also offer a skip action for lessons that are still running. Skipping a lesson does not corrupt the save, but it removes the guided practice for that topic.")

h2_section("3.3 Understanding the First Screen")
para("SandEE uses the same information architecture on both platforms, but the input hints differ. On PC, the bottom-right corner shows keyboard and mouse hints; on Android, the same corner contains the SPRINT and INTERACT buttons, and the bottom-left contains the BUILD button or the virtual joystick. The following two figures show the first playable view on each platform.")
figure_page(
    "First Playable View: PC and Android",
    [
        (SHOTS / "pc_overworld.png", "PC gameplay HUD in the overworld. The minimap, mission tracker, Automatica status, health and stamina bars, hotbar, and desktop key hints are visible."),
        (SHOTS / "mobile_overworld.png", "Android gameplay HUD with the virtual joystick, BUILD and INTERACT controls, SPRINT toggle, and the reserved INV slot."),
    ],
)

h2_section("3.4 Reading the HUD")
para("The HUD is organized around four corners and a central play area. The top-left contains the minimap. The top-right contains the star totals, the mission tracker, and the PAUSE button; during onboarding the mission tracker and star total stay hidden until the tutorial ends, except while the Automatica mission lesson explains them. The bottom-centre contains the health bar, stamina bar, and hotbar. The left-middle contains the Automatica status panel. The bottom-right contains contextual controls: key hints on PC, and SPRINT and INTERACT on Android.")
bullet_item("Minimap: shows the player, nearby creatures, Bonfires, Automatica stations, dungeon entrances, and Skyglass Waypoints. Dungeon entrances carry a pulsing halo, the recommended next one is emphasized in teal, and a dungeon map pulses its current objective. Click it or press M on PC to open the full map.")
bullet_item("Mission tracker: shows up to three active gameplay missions, with dungeon rows for the current Lua and Python tracks. The VIEW ALL MISSIONS button opens the full mission log, which lists active main, dungeon and side missions first and collects completed missions in a section at the bottom.")
bullet_item("Health and stamina: health is a maximum of 100; stamina is a maximum of 50. The bars are always visible during normal gameplay.")
bullet_item("Hotbar: nine slots on PC, eight item slots plus INV on Android. The selected slot is highlighted.")
bullet_item("Automatica status: shows the three most recently updated robots and their current job. Click the panel to expand the full list.")

h2_section("3.5 First Objectives and Early Progression")
para("The first hour of play is designed to establish a repeatable loop: gather wood, craft a station, enter the first dungeon, learn a programming concept, and return to camp. The player does not need to optimize a base or accumulate food before starting the dungeon. The starter kit and the guided route are sufficient for the first clear.")
para("After the opening dungeon, the player should place the Crafting Station and open its Algorithmica panel at least once. The guided camp lesson uses a short Python program, and the Automatica lesson demonstrates a build-line example. These lessons are the bridge between the sandbox and the programming systems; skipping them makes the later automation objectives harder to interpret.")

h2_section("3.6 Saving and Resuming")
para("The game autosaves every 60 seconds while the player is alive and not in an unsafe transition. It also requests an autosave when mission progress changes, so a completed objective or a meaningful progress update is not left only in memory. Because mining, building, and crafting can update a mission several times in a few seconds, mission-triggered saves are throttled to at most once every five seconds. The game also saves when the player chooses Quit to Menu and when the Android app is backgrounded. The save includes terrain edits, placed blocks, container contents, machine state and programs, player position, missions, tutorial progress, dungeon state, Bestiary, and knowledge.")
para("If the game is closed unexpectedly, the most recent completed autosave is loaded. The save system writes to a temporary file and keeps a .bak safety copy; a crash during a write should leave either the previous save or the backup intact. This is what the code comments call an atomic save: the main save is not replaced until the new file has been written. If a world fails to load, check the Cloud Saves screen before attempting manual file changes.")

# ── Chapter 4 ──────────────────────────────────────────────────────
h1_chapter("CHAPTER 4: PLATFORM CONTROLS AND INTERFACE")
h2_section("4.1 PC Controls")
para("The PC build uses a conventional keyboard-and-mouse scheme. Movement is camera-relative; the mouse aims swings and determines the target tile for placement and interaction. Table 3 lists the default bindings. Bindings for movement, inventory, and the nine hotbar slots can be changed in Settings > Controls.")
add_table(
    ["Action", "Default binding", "Notes"],
    [
        ("Move", "WASD or arrow keys", "Camera-relative; diagonal movement is normalized."),
        ("Sprint", "Hold Shift", "Drains stamina; stops at zero and needs 15 stamina to restart."),
        ("Swing / use / attack", "Left mouse button", "Uses the held item; hold for repeated swings."),
        ("Aim", "Mouse pointer", "Swings and sword grass cuts follow the pointer."),
        ("Open / close inventory", "E", "Opens the Inventory, Craft, Encyclopedia, and Bestiary tabs."),
        ("Select hotbar slot", "1-9 or mouse wheel", "The selected slot is highlighted."),
        ("Toggle build mode", "Ctrl", "Place blocks, floors, doors, stations, and furniture."),
        ("Open / close map", "M", "The full map supports pan and zoom."),
        ("Pause / back / cancel", "Esc", "Closes the innermost panel or cancels a tap-to-move order."),
        ("Advance dialogue", "Enter or Space", "Also used by tutorial and NPC dialogue."),
        ("Destroy placed object", "Shift + click", "Mines a block, chest, station, or furnace instead of using it."),
        ("Toggle control hints", "F1", "Shows or hides the bottom-right key hints."),
    ],
    [1.55, 1.6, 2.85],
    "Default PC controls.",
)

h2_section("4.2 PC Interface and Menus")
para("The PC interface exposes the same information as the Android interface but uses keyboard hints instead of touch buttons. The pause menu is the central navigation surface: Resume returns to the world, Help & Documentation opens the in-game manual, Settings opens audio, display, gameplay, and control options, Automatica Management lists active robots with a NORMAL or COMBAT mode badge, and Quit to Menu saves and exits the world. The main menu and pause menu share the same settings panel and save the same values to the global settings file. Fresh audio defaults are 90% master, 70% music and 80% SFX volume. Figures 3 and 4 compare the pause menu on the two platforms.")
figure_page(
    "Pause Menu: PC and Android",
    [
        (SHOTS / "pc_pause.png", "PC pause menu. The same five actions are available on both platforms."),
        (SHOTS / "mobile_pause.png", "Android pause menu. Android Back closes the innermost panel before closing the pause menu."),
    ],
)

h2_section("4.3 Inventory and Item Management")
para("The inventory is a paused modal panel. On PC it opens with E; on Android it opens through the INV slot at the end of the hotbar. The panel has four tabs: Inventory, Craft, Encyclopedia, and Bestiary. The Inventory tab contains 20 player slots plus the hotbar. When a chest is open, its eight storage slots appear below the player slots.")
para("Items can be moved by dragging. Dragging a stack onto another stack merges it when the item type and stack limit allow it. Dragging a stack onto an empty slot moves it. Dragging a stack to the trash control deletes it after the drop is accepted. On Android, tap and hold an item to show its tooltip; on PC, hover the pointer over the item. Figures 5 and 6 compare the inventory panel on the two platforms.")
figure_page(
    "Inventory: PC and Android",
    [
        (SHOTS / "pc_inventory.png", "PC inventory panel with the Inventory, Craft, Encyclopedia, and Bestiary tabs."),
        (SHOTS / "mobile_inventory.png", "Android inventory panel. The hotbar remains visible and interactive while the panel is open."),
    ],
)

h2_section("4.4 PC Build Mode")
para("Build mode is toggled with Ctrl on PC. A translucent block ghost and a tile grid appear around the player. The player may place within six blocks of their position. A red ghost means the target is occupied, in water, too far away, or blocked by the player; a white ghost means the placement is valid. Floors are walkable and render below the player; walls block movement; doors can be opened and closed with a plain click.")
para("The selected hotbar slot determines what is placed. Build mode is disabled inside dungeons, and placement is blocked on dungeon or portal footprints and unopened cave entrances. To remove a placed object, Shift + click it. If the player is holding a suitable pickaxe, or an axe on a wooden object, a plain click also destroys it; this is the primary demolition path on Android. Figures 7 and 8 compare the build-mode interface on the two platforms.")
figure_page(
    "Build Mode: PC and Android",
    [
        (SHOTS / "pc_build_mode.png", "PC build mode with the placement grid, ghost preview, and a valid white target."),
        (SHOTS / "mobile_build_mode.png", "Android build mode. The BUILD button changes to BUILD ON and the grid is placed with a tap."),
    ],
)

h2_section("4.5 Android Controls")
para("The Android build replaces the keyboard and mouse with a virtual joystick, direct taps, and four context buttons. Table 4 lists the default touch controls. The joystick is hidden when point-and-click movement is enabled; in that mode, tapping the ground issues a move order and tapping a target walks to it and interacts.")
add_table(
    ["Action", "Android control", "Notes"],
    [
        ("Move", "Left virtual joystick", "A second finger can use buttons and the hotbar while moving."),
        ("Sprint", "SPRINT toggle", "Tap once to sprint, tap again to walk. Stamina rules are identical to PC."),
        ("Swing / use / attack", "Tap the world", "The held item determines the action."),
        ("Build mode", "BUILD button", "Changes to BUILD ON while active; tap the world to place."),
        ("Interact", "INTERACT button", "Opens a nearby chest, station, furnace, or Color Crafter."),
        ("Inventory", "INV slot", "The last hotbar slot is reserved for inventory on Android."),
        ("Back / close panel", "Android Back", "Closes the innermost panel or menu."),
        ("Dismiss keyboard", "DONE", "Appears above the on-screen keyboard while a text field is focused."),
        ("Item tooltip", "Tap and hold", "Shows the item description and properties."),
        ("Destroy placed object", "Tap with a suitable tool", "A pickaxe or axe destroys the target; otherwise use the desktop Shift + click equivalent where available."),
    ],
    [1.45, 1.7, 2.85],
    "Default Android touch controls.",
)

h2_section("4.6 Cross-Platform Differences")
para("The two builds share the same world, save format, missions, and programming systems. The differences are input and presentation:")
bullet_item("PC has a persistent mouse cursor, hover tooltips, keyboard hints, and a 9-slot hotbar. Android has a virtual joystick, touch buttons, tap-and-hold tooltips, and an 8-slot hotbar with INV.")
bullet_item("PC uses Shift + click to destroy placed objects. Android uses a suitable pickaxe or axe and a direct tap; this is also available on PC.")
bullet_item("Android Back closes the innermost panel. On PC, Esc performs the same role.")
bullet_item("The Android UI respects cutouts, notches, system bars, 180-degree rotation, and the soft-keyboard height. UI scale is computed automatically; the desktop build uses the same responsive scale but with a larger minimum.")
bullet_item("The custom cursor is desktop-only. Android uses the emulated pointer and standard touch feedback.")
para("Point-and-click movement is optional on both platforms. When enabled, clicking or tapping the ground walks there; clicking an interactable walks to one-block range and opens or interacts without swinging the held item; clicking a hostile creature chases and attacks it. Manual movement cancels the order. Automatic Sprint uses stamina exactly like the Shift key or the Android SPRINT toggle. A solid wall or object with no walkable approach or route is rejected immediately instead of walking the player into it.")

# ── Chapter 5 ──────────────────────────────────────────────────────
h1_chapter("CHAPTER 5: CORE GAMEPLAY")
h2_section("5.1 Movement, Sprinting, and Stamina")
para("Movement is camera-relative on PC and joystick-relative on Android. Diagonal movement is normalized so moving diagonally is not faster than moving orthogonally. Sprinting multiplies movement speed and drains stamina at 10 points per second; stamina regenerates at 5 points per second while not sprinting. When stamina reaches zero, the player becomes exhausted and cannot sprint again until stamina reaches 15.")
para("Sprint is useful for crossing open terrain, escaping a group of hostiles, and reaching a dungeon entrance before night. It is less useful inside a confined cave or dungeon, where collisions and hazards make the extra speed difficult to control. The Android SPRINT toggle is latched: tapping it once enables sprint until it is tapped again or stamina is exhausted.")

h2_section("5.2 Health, Food, and Death")
para("The player has 100 maximum health. There is no hunger or thirst meter. Food is a healing item: select it in the hotbar and click or tap to eat. The click must not be aimed at a solid object, because that click is treated as an interaction with the object instead. The player cannot eat at full health.")
para("Cooked fish restore 50 health, Bread restores 20, and apples and raw meat restore smaller amounts. Fish must be cooked in a Furnace before they restore the full amount. If health reaches zero, the player dies, drops no inventory, and respawns in the overworld at the active Bonfire or at the world spawn if no Bonfire is active. Death cancels build mode and pending actions. Dying in a cave or dungeon still returns the player to the overworld; the death overlay and respawn timer make the transition explicit.")

h2_section("5.3 Day, Night, Weather, and Biomes")
para("A full day/night cycle lasts 24 real minutes: approximately 12 minutes of day and 12 minutes of night. The world starts at noon. Night raises the hostile population cap and spawn rate, and some creatures appear only at night. Creatures that naturally spawn during the day take 40% less damage from every hit, which makes daytime combat slower but not impossible.")
para("Biomes include plains and forest, desert, snowy land, water, the overworld ocean edge, caves, Pixie Caves, and dungeons. Entering the desert can spawn a group of Desert Worms. Snow biomes can trigger a snowstorm with heavy particles, reduced visibility, and movement at 55% speed. A snowstorm ends when the player leaves the snow or when night falls. Snowfall and biome ambience are visual and do not damage the player by themselves.")
para("Sunshard Finches fly overhead in daytime flocks, and Dusk Kites replace them at night. Both are harmless ambience. The Bestiary records them as sightings, but they are not combat targets.")

h2_section("5.4 Gathering, Mining, and Tool Tiers")
para("Most resources are gathered by holding the left mouse button on a block or by tapping it on Android. A break ring shows progress, and progress on the same tile is remembered for a short time between clicks. Blocks have a minimum pickaxe tier: the Wooden Pickaxe is tier 1 and mines stone, iron, and copper; the Iron Pickaxe is tier 5; the Diamond Pickaxe is tier 10 and reaches diamond ore. While the mine button remains held, the next placed block or cave wall/ore under the cursor starts breaking automatically; releasing the button stops the chain.")
para("Axes speed up wood and wooden blocks. Swords cut grass and harvest mature wheat. Torches light the area at night and inside caves and dungeons; a torch placed beside a wall uses the connected-wall visual. Tools are not consumed by use, but they occupy inventory slots and can be moved between the hotbar and inventory.")

h2_section("5.5 Inventory, Hotbar, and Containers")
para("The inventory contains 20 player slots plus the hotbar. The hotbar has nine slots on PC and eight item slots plus INV on Android. Items stack up to their individual stack limit; tools generally do not stack. The inventory panel also hosts the Craft, Encyclopedia, and Bestiary tabs, so it is the main information surface outside the pause menu.")
para("Chests hold eight stacks and open inside the inventory panel. A chest's contents are saved with the world. Rare dungeon chests contain automation materials and food. The trash control deletes a dragged stack after the drop is accepted; it is not an undoable action.")

h2_section("5.6 Farming, Water, and Fishing")
para("Farming begins with grass. Cutting grass with a sword has a 25% chance to drop Wheat Seeds. The Iron Hoe tills a grass tuft into Tilled Ground, but the plot must be within 20 blocks of water. Select Wheat Seeds in build mode and click the tilled plot to plant. Wheat ripens in 3 real minutes; cut the mature crop with a sword to harvest 1-3 Wheat and a 50% chance of a seed. Three Wheat make one Bread.")
para("An empty Bucket clicked on water becomes a Water Bucket. A Water Bucket clicked on ground pours a water source. Water blocks movement but can be bridged with blocks; it is required for tilled plots and can be moved to create a farm anywhere. Cacti grow in the desert over time and are used by the Color Crafter and as high-level furnace fuel.")
para("Fishing requires the Fishing Rod. Select the rod and click or tap water within 8 blocks. The cast takes 5 seconds and has a 70-90% catch chance. Moving more than about two tiles, unequipping the rod, or leaving the scene cancels the attempt. The catch is one of Yellow Carp, Scuttlefish, Eelfish, or Anglefish; cook the fish in a Furnace to restore 50 health each.")

h2_section("5.7 Shelter and Safe Rooms")
para("A valid house is a sealed room with a door and at least a 3x3 interior. Houses suppress ambient hostile spawns and darken the world outside while the player is indoors. The same room rule drives the shelter tracker. Floors are walkable and render beneath the player; walls block movement; doors can be opened and closed with a plain click.")
para("Dungeon Knowledge Altar rooms contain green safe-zone markers. Stepping on one makes the player invulnerable, heals 1 health per second, and disintegrates hostiles inside the room. A safe zone lasts 30 seconds and then needs 20 seconds to re-arm. Leaving the room ends it early. Safe-zone kills grant no loot or Bestiary credit, so they are a survival tool rather than a farming method. Quiz rooms are combat rooms and are not safe zones.")

# ── Chapter 6 ──────────────────────────────────────────────────────
h1_chapter("CHAPTER 6: BUILDING AND CRAFTING")
h2_section("6.1 Build Mode")
para("Build mode is the main construction interface. Press Ctrl on PC or tap BUILD on Android. A translucent block ghost and a tile grid appear. The player may place within six blocks of their position. A red ghost means the target is occupied, in water, too far away, or blocked by the player. A white ghost means the placement is valid. The selected hotbar slot determines what is placed.")
para("Floors are walkable and render below the player. Walls block movement. Doors can be opened and closed with a plain click. Build mode is disabled inside dungeons, and placement is blocked on dungeon or portal footprints and unopened cave entrances. To remove a placed object, Shift + click it on PC. On Android, tap it with a suitable pickaxe or axe; this also works on PC and is the recommended demolition path for touch players.")

h2_section("6.2 Blocks, Doors, Torches, and Bonfires")
para("Placeable blocks include natural materials, crafted building blocks, floors, doors, torches, stations, furniture, and decorative objects. A placed block occupies one tile. Floors are an exception: they are walkable ground and can sit underneath another placed block, so a floor survives when a wall or station is placed on top of it.")
para("Doors toggle between closed and open with a plain click. A closed door is solid; an open door is passable. Torches and Bonfires are light sources and are non-solid. Bonfires are also respawn points: a plain click activates one, and clicking it again clears it. Only one Bonfire can be active at a time, and only in the overworld. Breaking the active Bonfire resets respawn to the world spawn. Torches and Bonfires do not use a fuel timer.")

h2_section("6.3 The Crafting Station")
para("The Crafting Station is a placeable machine and the main crafting surface. Place it from the hotbar, then plain-click it to open the station menu. The manual crafting view groups recipes into categories such as Materials, Blocks, Weapons & Tools, and Others. Choose a recipe, check the ingredient list, and press CRAFT. Manual crafting delivers the result directly to the player's inventory.")
para("Station recipes include planks, doors, floors, torches, chests, tools, weapons, and the Furnace. The station also hosts the Algorithmica panel, a code-only Python interface for selecting recipes, crafting items, crafting colored blocks, and collecting output. Manual crafting and Algorithmica share the station's input slot and output slot, so a program can consume materials that were loaded by hand.")
note_item("If the inventory is full when a manual craft completes, the result is dropped at the player's feet instead of being deleted. The station still consumes the ingredients, so clear inventory space before starting a large batch.")

h2_section("6.4 The Furnace")
para("The Furnace smelts ore, cooks food, and converts wood into charcoal. Load a smeltable item into INPUT and a fuel item into FUEL, then press SMELT. Each smelt takes 5 seconds and consumes one input plus one fuel whose fuel level meets the recipe requirement. Wood, Birch Wood, Snowy Wood, planks, Charcoal, and Cactus are fuels; Charcoal has fuel level 2 and Cactus has fuel level 5.")
para("Typical smelts include Copper Ore to Copper, Iron Ore to Ironbar, Silicon Ore to Silicon, Diamond Ore to Diamond, crystal ore to its base material, Wood to Charcoal, and raw fish or dog meat to cooked food. The furnace previews the output before the player commits. It cannot smelt without fuel or without output space. Output can be taken from the furnace slot or through Algorithmica's take_output().")

h2_section("6.5 The Color Crafter")
para("The Color Crafter produces solid-color building blocks. Craft the machine with 20 Cactus and 10 Ironbar, place it, and plain-click it. Pick a color with the wheel, the RGB sliders, or the numeric R/G/B fields, then craft. Each block costs one Cactus. Pure black and pure white are rejected. The result is a placeable block that saves its RGB value.")
para("Algorithmica can perform the same operation from a Crafting Station with craft_color(r, g, b, amount), where amount is between 1 and 32. Color blocks are normal building blocks and can be mined and placed like other blocks. The Color Crafter is therefore both a manual design tool and an automation target.")

h2_section("6.6 Containers and Machine State")
para("Chests, stations, furnaces, and Color Crafters save their contents and state with the world. A station's program text, a furnace's input/fuel/output, and a container's stacks are restored on load. This makes a built production line persistent: the player can leave the world, return, and find the machines in the same state.")
para("Machine state also includes the station's selected recipe and output, the furnace's cooking progress, and the Color Crafter's last color. If a machine appears to do nothing, check its input, fuel, output space, and tool slot before assuming a bug. The troubleshooting table in Chapter 9 lists the most common causes.")

# ── Chapter 7 ──────────────────────────────────────────────────────
h1_chapter("CHAPTER 7: PROGRAMMING AND AUTOMATION")
h2_section("7.1 The Programming Encyclopedia")
para("The Programming Encyclopedia is the in-game API reference. It is available from the inventory's Encyclopedia tab. Function lists are always visible; language concepts unlock through dungeon Knowledge Altars. The encyclopedia describes every Automatica and Algorithmica function, the mineable block names, and the station and furnace templates. It is the authoritative reference when this manual and the build disagree.")
para("The encyclopedia is also a teaching progression. Reading a Knowledge Altar records an entry for that world and unlocks its keyword. The archive can be paged, so a player who has cleared several dungeons can review earlier concepts without revisiting the altar. Knowledge is saved per world.")

h2_section("7.2 Automatica and Lua")
para("Automatica is the Lua-controlled robot companion. Craft or obtain an Automatica item, select it, and place it like a block. Plain-click the station to open its console. The editor mirrors Algorithmica's layout with CODE, INVENTORY and ENCYCLOPEDIA tabs. The CODE tab holds the TEMPLATES column, the Lua editor, RUN/STOP controls and an inline output log; INVENTORY holds the tool slot and three build slots. The robot executes Lua against the real world; progress and messages appear under the code editor.")
para("Right-click the station to toggle its blue work-radius ring. The default radius is 20 blocks, and radius-based calls support 1 to 64 blocks. Drag items into the robot's inventory and build slots, or use withdraw(\"name\", n) to pull from a nearby chest. The tool slot is required for mine() and attack(). Common calls include auto_work(), chop_trees(radius), deposit_chest(), return_to_spawn(), mine(\"stone_block\"), place_item(), build_line(), build_rect(), build_circle(), set_recipe(), craft(n), put_input(), and take_output().")
para("A world can hold up to 31 Automatica stations. Each station has independent code, inventory, and build slots. combat_mode(true) turns the robot into a follower with 250 HP that follows through caves and dungeons and attacks nearby hostile mobs with its tool. A combat Automatica cannot run code. Click the follower (or its station) and press EXIT COMBAT, or run combat_mode(false), to return it to its blue station form. A combat Automatica can also be permanently terminated from Pause > Automatica Management.")
add_code_block("""-- Example: build a short path, then craft planks
select_block(0)
build_line(-15, -8, 16, -8)

-- Load wood, craft planks, and collect the output
select_block(0)
input_slot(5)
set_recipe("Planks")
craft(5)
take_output()""")
note_item("A robot's work radius is measured from its station, not from its current position. If a job reports that a target is out of range, move the station or use a radius call that reaches the target. The robot returns to its station before going idle so it is not left stranded far from home.")

h2_section("7.3 Algorithmica and Python")
para("Algorithmica is the Python automation panel inside Crafting Stations and Furnaces. Open a station or furnace and press its ALGORITHMICA button. The editor is code-only: the player writes Python that calls the machine's functions, then presses RUN. The panel shows output and errors in a log below the code.")
para("Crafting Station calls include set_recipe(\"Planks\"), craft(n), get_recipe(), output_item(), output_count(), take_output(), and craft_color(r, g, b, n). Furnace calls include feed(\"Iron Ore\", n), fuel(\"Charcoal\", n), smelt(n), take_output(), input_name(), input_count(), fuel_name(), fuel_count(), output_name(), and output_count(). Programs run against the machine's real slots. Load input and fuel first, or use feed() and fuel(); smelt() consumes one fuel per item. Output stays in the machine until take_output().")
add_code_block("""# Example: smelt five iron bars
feed("Iron Ore", 5)
fuel("Charcoal", 5)
smelt(5)
take_output()""")
para("The TEMPLATE button loads a complete station or furnace example, and COLOR loads a craft_color example. The RECIPES button prints every recipe and its scripting item identifier. The editor prevents adding new Python functions, but recipe discovery is built in. Python and Lua are separate interpreters: a station's Python code is not run by Automatica, and Automatica cannot run a station's Python panel.")

h2_section("7.4 A Practical Automation Workflow")
para("A reliable first automation loop is a plank factory. Place a Crafting Station near a chest and an Automatica station. Put Wood in the chest and a Wooden Axe in the Automatica tool slot. Write a Lua program that withdraws Wood, loads the station input, selects the Planks recipe, crafts a batch, takes the output, and deposits the planks back into the chest. Run the program once, inspect the output log, then increase the batch size.")
para("A second loop is a furnace line. Place a Furnace beside a chest, load Iron Ore and Charcoal, and write a Python program that feeds five ore, adds five fuel, smelts five bars, and takes the output. The furnace consumes one fuel per item, so the fuel count must match the ore count. If the output slot fills, the program stops accepting new input; take the output before starting the next batch.")
para("These loops are intentionally small. Once the player understands the input/output contract, the same pattern scales to colored blocks, cooked fish, charcoal, and multi-machine workshops. The Programming Encyclopedia's function descriptions are the reference for exact argument names and return values.")

h2_section("7.5 Robots in Combat")
para("Combat mode turns an Automatica into a mobile fighter. The robot follows the player through caves and dungeons and attacks the nearest hostile mob on its own cooldown, independent of the player's swings. It has 250 HP and takes contact damage from mobs. It also automatically parries nearby DungeonProjectile bolts from flare vents or Hitmen when they are heading for itself or the player it escorts, using a short defensive cooldown. It cannot run code while in combat mode. Click the follower (or its station) and press EXIT COMBAT, or run combat_mode(false), to send it back to its station as a normal blue Automatica. The player can also terminate a combat robot permanently from Pause > Automatica Management; termination frees the station for another robot. Figure 9 shows the Automatica editor, and Figure 10 shows a Lua dungeon chamber used by the programming track.")
figure_page(
    "Programming and Dungeon Examples",
    [
        (SHOTS / "code_editor_crop.png", "Automatica Lua code editor. The TEMPLATES column, code pane, RUN/STOP controls and inline output log are visible."),
        (ROOT / "website" / "assets" / "img" / "screenshots" / "dungeon-lua-01.jpg", "A Lua dungeon chamber. Dungeons combine programming lessons with combat, traps, and treasure."),
    ],
)

h2_section("7.6 Limitations and Good Practices")
bullet_item("Keep programs small at first. A short loop that succeeds is easier to debug than a large program that fails silently.")
bullet_item("Check the output log after every run. A program that produces no error can still be waiting for input, fuel, or output space.")
bullet_item("Use exact item identifiers. The RECIPES button and the Programming Encyclopedia list the identifiers; display names with spaces are not always valid arguments.")
bullet_item("Do not run a combat Automatica's code. Combat mode is a terminal state for the current robot; terminate it or use a different station.")
bullet_item("Remember that station input and player inventory are different sources. A station consumes its input slot first, then the player's inventory, depending on the operation.")

# ── Chapter 8 ──────────────────────────────────────────────────────
h1_chapter("CHAPTER 8: COMBAT, DUNGEONS, AND PROGRESSION")
h2_section("8.1 Combat Basics")
para("Combat uses the held item. A sword deals damage equal to its sword level plus three; higher tiers increase both damage and the vertical slash radius. Level 1-3 swords cover one tile, level 4-6 cover three tiles, and level 7+ cover five tiles. The slash column is screen-vertical and centered on the tile in front of the player. Non-sword tools can still swing, but their damage and effects are defined by the item.")
para("Hostile mobs deal contact damage on a cooldown and knock the player back. The player has 0.3 seconds of invincibility after a landed hit, so repeated contact does not drain health instantly. Food is the primary healing item; the player should carry cooked fish or Bread into a dungeon. Death does not delete the inventory, but it cancels build mode and pending actions.")

h2_section("8.2 Creatures and the Bestiary")
para("The Bestiary records creatures that the player has seen and studied. A sighting shows the name, portrait, and category. Defeating the creature once reveals its field notes, maximum health, and complete drop table. Bestiary state is per world and saved. Safe-zone disintegrations do not count as kills, so the player must defeat the creature normally to study it.")
para("Categories include Friendly, Overworld, Lua Dungeon, and Python Dungeon creatures. The Bestiary is also a planning tool: it shows what a creature drops and how much health it has, which helps the player decide whether to fight or avoid it. Some creatures are harmless ambience; others are hostile only at night or only in a specific biome.")

h2_section("8.3 Dungeon Structure")
para("Each active language track has one overworld dungeon entrance. Walk onto the entrance and confirm Enter, or click its door. A temporary one-way waypoint appears near the player or camp; step on it to travel to the current dungeon entrance. The waypoint is consumed on use and is saved. A persistent route trail, marker and compass point to the recommended next track, alternating from the dungeon cleared last: clearing Python recommends Lua, and clearing Lua recommends Python. Clearing a dungeon removes its overworld entrance and spawns the next mission in that language's track.")
para("Dungeons are combat gauntlets with traps, flame vents, hostile spawns, and treasure chests. The first safe room contains a Knowledge Altar. Opening it and pressing Continue learns a programming concept permanently for that world; opening it and walking away does not count. The altar also keeps a pageable archive of every entry the player has learned. Every dungeon run draws a dotted-circle floor route to its current objective: the Knowledge Altar first, then the Quiz Altar. The route follows real floor cells and avoids trap tiles. The finale points at the Hitman Miniboss and then its opened exit. Figures 11 and 12 show representative Python and Lua dungeon chambers.")
figure_page(
    "Dungeon Environment Examples",
    [
        (ROOT / "website" / "assets" / "img" / "screenshots" / "dungeon-python-01.jpg", "A Python dungeon chamber. The masonry and lighting theme differs from the Lua track."),
        (ROOT / "website" / "assets" / "img" / "screenshots" / "dungeon-lua-02.jpg", "An alternate Lua dungeon chamber used for route, trap, and encounter examples."),
    ],
)

h2_section("8.4 Knowledge Altars")
para("The Knowledge Altar is the dungeon's teaching station. It presents a short entry, records it in the player's encyclopedia, and unlocks its keyword. The first dungeon's altar is part of the guided route; later dungeons use the altar to introduce language-specific concepts. The altar does not require a quiz answer to record the entry, but the player must open the altar and press Continue to learn it; opening it or walking away is not enough.")
para("The altar also hosts an archive of previously learned entries. The archive is pageable and can be opened without relearning an entry. Knowledge is saved per world, so a new world starts with an empty archive and a fresh tutorial.")

h2_section("8.5 Quiz Altars and Dungeon Clear")
para("The final room contains a Quiz Altar. For main dungeons it stays sealed behind a gold padlock until the linked Knowledge Altar entry has been learned, so the teaching step cannot be skipped. Answer every multiple-choice or compiler question correctly to clear the dungeon. Wrong answers can be retried; compiler questions run the player's code and check its output. HINT prepares the current answer: it fills compiler code with the expected print program or highlights the correct multiple-choice button. It becomes NEXT, which only dismisses the hint. The player still presses RUN or taps the answer.")
para("Each hint costs one blue star except during the first dungeon, and each wrong code run also costs one. A dungeon starts at three stars, and the score stops at zero but never blocks completion. Review the results and press Done to return to the overworld. Clearing the dungeon awards its mission star and advances the language track.")

h2_section("8.6 The Hitman Finale and Side Missions")
para("After both main language tracks, the shared Hitman miniboss dungeon unlocks. Defeating the Hitman completes the main story. Clearing it together with the main tracks and any extra dungeons unlocks the side missions. Side missions use the same star and progress system and appear in their own tracker section.")
para("The main mission flow is 12 Automatica objectives followed by 12 Algorithmica objectives. Automatica objectives cover programming, chopping, building, mining, and combat. Algorithmica objectives cover crafting, colored blocks, and furnace work. Dungeon rows start at three blue stars; other missions award a star when completed. Mission, star, side-mission, and dungeon-clear progress are stored in the world save.")

h2_section("8.7 Dungeon Survival Checklist")
bullet_item("Carry cooked food, a sword, a pickaxe, and at least one stack of blocks for bridging or blocking a corridor.")
bullet_item("Read the Knowledge Altar before the quiz; the Quiz Altar is locked until the entry is learned, and the entry is permanent and does not cost a star.")
bullet_item("Follow the dotted-circle floor route. It avoids trap tiles and always leads to the current objective, first the Knowledge Altar and then the Quiz Altar.")
bullet_item("Do not treat a safe zone as a farming spot. Safe-zone kills give no loot or Bestiary credit.")
bullet_item("Check the mission tracker after a clear. The next language mission and the Hitman finale appear there.")
bullet_item("Completing a mission briefly shows its name in a top-centre notification, styled like the autosave indicator.")

# ── Chapter 9 ──────────────────────────────────────────────────────
h1_chapter("CHAPTER 9: SAVING, ACCOUNTS, AND TROUBLESHOOTING")
h2_section("9.1 Saving")
para("The game autosaves every 60 seconds while the player is alive and not in an unsafe transition. It also requests an autosave when mission progress changes, throttled to at most once every five seconds so rapid mining, building, or crafting updates do not write the save file repeatedly. It also saves when the player chooses Quit to Menu and when the Android app is backgrounded. Each world is a save slot. The save includes the world seed, terrain edits, placed blocks, container contents, machine state and programs, player position, missions, tutorial progress, dungeon state, Bestiary, and knowledge.")
para("The save system writes to a temporary file and keeps a .bak safety copy. A crash during a save should leave either the previous save or the backup intact; the main save is not replaced until the new file has been written. The main menu's Worlds screen creates, loads, renames, and deletes worlds. Deletion is permanent for that device.")

h2_section("9.2 Cloud Saves and Offline Play")
para("An online account is required before worlds can be created or opened. Worlds upload automatically after saves and download during the sign-in sync. Each account sees only its own cloud-backed worlds. Two devices sharing the same world use the newer save revision when the world identifier matches.")
para("A cloud save in a slot with a different world identifier is treated as a protected conflict. The game does not overwrite it automatically; open Cloud Saves and download a copy to restore it locally. Play Offline uses the previously verified local copies belonging to the currently signed-in account. Other accounts' worlds are never listed, and new worlds require an online session. If an account switch or cleanup is interrupted, world access stays blocked until the account is verified again.")

doc.add_page_break()
h2_section("9.3 Troubleshooting")
para("Table 5 lists the most common player-facing problems and the first corrective actions. If a problem persists, capture the on-screen message, the world name, the platform, and the approximate time, then report it through the project's issue channel.")
add_table(
    ["Symptom", "Likely cause", "Action"],
    [
        ("Game does not start on PC", "Incomplete extraction or missing runtime file", "Re-extract the complete ZIP; do not run from inside the archive. Update the graphics driver."),
        ("Black screen after launch", "World generation still running", "Wait for the loading screen to finish. If it persists, restart and check the log."),
        ("No sound", "Master, Music, or SFX muted", "Open Settings > Audio and raise the three sliders. Check the OS volume and output device."),
        ("Android blocks the APK", "Unknown-app installation disabled", "Allow the file manager or browser to install unknown apps, then retry."),
        ("Inventory or menu will not close", "A panel is waiting for Back/Esc", "Press Esc on PC or Back on Android. Close the innermost panel first."),
        ("World missing after sign-in", "Cloud save not downloaded or different account", "Open Cloud Saves and download the copy. Confirm the account identity."),
        ("Furnace will not smelt", "Missing fuel, wrong fuel level, or full output", "Load valid fuel, clear the output slot, and check the recipe."),
        ("Robot does not mine or attack", "Tool slot empty or target out of range", "Place the required tool in the robot's tool slot and check the station radius."),
        ("Algorithmica name error", "Wrong item id or foreign function", "Use the RECIPES button and the Programming Encyclopedia for exact names."),
        ("Low frame rate", "Large world, many entities, or background apps", "Close background apps, lower the window size, and avoid dense automation loops while exploring."),
    ],
    [1.55, 1.9, 2.55],
    "Common problems and corrective actions.",
)

h2_section("9.4 Performance and Stability Tips")
bullet_item("Do not run large automation loops while exploring a new biome. The robot and the ambient spawn director both consume simulation time.")
bullet_item("Keep the number of active Automatica stations reasonable. Each station has its own code, inventory, and build slots; many simultaneous robots increase CPU load.")
bullet_item("Close unused panels before a dungeon transition. The game pauses while a modal is open, and a transition can look like a freeze if a panel is left open.")
bullet_item("On Android, close background apps before generating a new world. World generation is the most memory-intensive operation.")
bullet_item("Use cloud saves before changing devices or uninstalling the Android app. Local app data is removed on uninstall.")

h2_section("9.5 Reporting a Problem")
para("A useful report includes the platform, game version, world name, a short description of the action that triggered the problem, the exact on-screen message, and whether the problem reproduces after reloading. Screenshots or a short recording are helpful for interface problems. For save or cloud problems, state whether the world was created online, whether it was opened through Play Offline, and whether a conflict message appeared.")

# ── Appendix A ─────────────────────────────────────────────────────
h1_chapter("APPENDIX A: QUICK REFERENCE")
h2_section("A.1 PC Quick Reference")
add_table(
    ["Action", "Binding"],
    [
        ("Move", "WASD / arrows"),
        ("Sprint", "Hold Shift"),
        ("Swing / use / attack", "Left mouse"),
        ("Aim", "Mouse pointer"),
        ("Inventory", "E"),
        ("Hotbar", "1-9 / mouse wheel"),
        ("Build mode", "Ctrl"),
        ("Map", "M"),
        ("Pause / back", "Esc"),
        ("Dialogue", "Enter / Space"),
        ("Destroy placed object", "Shift + click"),
        ("Control hints", "F1"),
    ],
    [3.0, 3.0],
    "PC quick reference.",
)

h2_section("A.2 Android Quick Reference")
add_table(
    ["Action", "Control"],
    [
        ("Move", "Left joystick"),
        ("Sprint", "SPRINT toggle"),
        ("Swing / use / attack", "Tap the world"),
        ("Build mode", "BUILD / BUILD ON"),
        ("Interact", "INTERACT"),
        ("Inventory", "INV slot"),
        ("Close panel", "Back"),
        ("Dismiss keyboard", "DONE"),
        ("Item tooltip", "Tap and hold"),
        ("Destroy placed object", "Tap with pickaxe/axe"),
    ],
    [3.0, 3.0],
    "Android quick reference.",
)

h2_section("A.3 First-Run Checklist")
bullet_item("Extract the complete PC ZIP or install the Android APK.")
bullet_item("Sign in or use the verified offline path.")
bullet_item("Create a world and complete the movement, chopping, and crafting lessons.")
bullet_item("Open the inventory and read the Craft, Encyclopedia, and Bestiary tabs.")
bullet_item("Enter the first dungeon, read the Knowledge Altar, and clear the Quiz Altar.")
bullet_item("Open the Crafting Station's Algorithmica panel and run the template program.")
bullet_item("Place an Automatica station and run the build-line example.")
bullet_item("Set a Bonfire respawn point before exploring at night.")

# ── Appendix B ─────────────────────────────────────────────────────
h1_chapter("APPENDIX B: GLOSSARY")
glossary = [
    ("Algorithmica", "The Python automation panel inside Crafting Stations and Furnaces."),
    ("Automatica", "The Lua-controlled robot companion and its station."),
    ("Bestiary", "The per-world record of creatures seen and studied."),
    ("Bonfire", "A placeable, toggleable overworld respawn point. Only one can be active."),
    ("Build mode", "The placement mode toggled by Ctrl or BUILD."),
    ("Dungeon", "A language-themed combat and learning instance entered from the overworld."),
    ("Fog of war", "The unexplored area of the map that is revealed by movement."),
    ("Hotbar", "The quick-select item bar at the bottom of the screen."),
    ("Knowledge Altar", "A dungeon station that records a programming concept in the encyclopedia."),
    ("Lua", "The scripting language used by Automatica."),
    ("Pixie Cave", "A cave variant with crystal ore and pixie enemies. The first one is safe."),
    ("Python", "The scripting language used by Algorithmica."),
    ("Quiz Altar", "The final dungeon station that checks the player's answers and clears the dungeon."),
    ("Safe zone", "A temporary invulnerable room triggered by a green marker in a Knowledge Altar room."),
    ("Skyglass Waypoint", "A permanent overworld tower used for fast travel."),
    ("Stamina", "The sprint resource. Maximum 50; exhaustion clears at 15."),
]
for term, definition in glossary:
    p = doc.add_paragraph(style="Manual Body")
    p.paragraph_format.first_line_indent = Inches(0)
    r = p.add_run(term + ". ")
    set_run_font(r, size=12, bold=True)
    p.add_run(definition)

# ── Appendix C ─────────────────────────────────────────────────────
h1_chapter("APPENDIX C: DOCUMENT REVIEW CHECKLIST")
para("This checklist is for the thesis or QA reviewer who will convert this draft into the final manual. It is not player-facing content.")
for item in (
    "Confirm the final game version and replace 0.9.4.8 in the title page, document control table, and header.",
    "Recapture the PC and Android screenshots after the interface freeze; keep at most two screenshots per page.",
    "Verify the minimum and recommended requirements against the exported builds.",
    "Check the installation filenames and package names against the release folder.",
    "Re-run the first-run checklist on a clean Windows profile and a clean Android device.",
    "Confirm that the 60-second autosave and the mission-progress autosave still match the build.",
    "Update the troubleshooting table with any new known issues.",
    "Update the Table of Contents, List of Figures, and List of Tables fields in Word.",
    "Export the final PDF with embedded fonts and confirm that all figures are legible at 100% zoom.",
):
    bullet_item(item)

para("End of draft.")

# ── Save ───────────────────────────────────────────────────────────
# Ask Word to refresh fields when the document is opened.
settings = doc.settings.element
update = settings.find(qn("w:updateFields"))
if update is None:
    update = OxmlElement("w:updateFields")
    settings.append(update)
update.set(qn("w:val"), "true")

OUT.mkdir(parents=True, exist_ok=True)
doc.save(DOCX)
print("WROTE", DOCX)
print("SIZE", DOCX.stat().st_size)
