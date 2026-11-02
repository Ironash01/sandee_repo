from __future__ import annotations

import argparse
import json
import os
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from docx import Document
from docx.enum.section import WD_SECTION
from docx.enum.table import WD_TABLE_ALIGNMENT, WD_ALIGN_VERTICAL
from docx.enum.text import WD_ALIGN_PARAGRAPH, WD_BREAK
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Cm, Pt, RGBColor, Emu
from PIL import Image

ROOT = Path(__file__).resolve().parent
DOCS = ROOT
MD_PATH = DOCS / "SandEE_User_Manual_Draft.md"
DOCX_PATH = DOCS / "SandEE_User_Manual_Draft.docx"
SHOT_ROOT = DOCS / "manual_assets" / "screenshots"

TITLE = "SandEE"
SUBTITLE = "An Educational Multi-Platform 2D Open World Survival Crafting Game for Lua and Python for ICT and STEM"
DATE = ""

BODY_FONT = "Times New Roman"
CODE_FONT = "Consolas"
BODY_SIZE = Pt(12)
CAPTION_SIZE = Pt(12)
TABLE_FONT_SIZE = Pt(12)
CODE_SIZE = Pt(10)

FIG_RE = re.compile(r"^!\[(.*?)\]\((.*?)\)\{#(fig:[A-Za-z0-9_-]+)\}\s*$")
TAB_CAP_RE = re.compile(r"^Table:\s*(.*?)\s*\{#(tab:[A-Za-z0-9_-]+)\}\s*$")
CHAPTER_RE = re.compile(r"^Chapter\s+(\d+)\.")
INLINE_RE = re.compile(r"(\*\*.+?\*\*|`.+?`|\*[^*]+\*)")
TOKEN_RE = re.compile(r"\{\{(fig|tab):([A-Za-z0-9_-]+)\}\}")


@dataclass
class Heading:
    level: int
    text: str


@dataclass
class Figure:
    fid: str
    caption: str
    path: str
    label: str


@dataclass
class Table:
    tid: str
    caption: str
    label: str
    headers: list[str]
    rows: list[list[str]]


@dataclass
class Block:
    kind: str
    text: str = ""
    level: int = 0
    figure: Figure | None = None
    table: Table | None = None
    items: list[str] = field(default_factory=list)
    lang: str = ""


class ManualParser:
    def __init__(self, md_path: Path):
        self.lines = md_path.read_text(encoding="utf-8").splitlines()
        self.blocks: list[Block] = []
        self.figures: list[Figure] = []
        self.tables: list[Table] = []
        self.headings: list[Heading] = []
        self.fig_by_id: dict[str, Figure] = {}
        self.tab_by_id: dict[str, Table] = {}
        self.chapter_no = 0
        self.fig_no = 0
        self.tab_no = 0
        self.pending_table_caption: tuple[str, str] | None = None
        self.errors: list[str] = []

    def parse(self) -> None:
        i = 0
        while i < len(self.lines):
            raw = self.lines[i]
            line = raw.rstrip()
            if not line.strip():
                i += 1
                continue

            m = re.match(r"^(#{1,3})\s+(.*)$", line)
            if m:
                level = len(m.group(1))
                text = m.group(2).strip()
                if level == 1:
                    cm = CHAPTER_RE.match(text)
                    self.chapter_no = int(cm.group(1)) if cm else 0
                    self.fig_no = 0
                    self.tab_no = 0
                self.headings.append(Heading(level, text))
                self.blocks.append(Block("heading", text=text, level=level))
                i += 1
                continue

            fm = FIG_RE.match(line)
            if fm:
                caption = fm.group(1).strip()
                rel = fm.group(2).strip()
                fid = fm.group(3).strip()
                path = DOCS / rel
                if not path.exists():
                    self.errors.append(f"Missing figure file: {rel}")
                if fid in self.fig_by_id:
                    self.errors.append(f"Duplicate figure id: {fid}")
                self.fig_no += 1
                label = f"Figure {self.chapter_no}.{self.fig_no}"
                fig = Figure(fid, caption, rel, label)
                self.figures.append(fig)
                self.fig_by_id[fid] = fig
                self.blocks.append(Block("figure", figure=fig))
                i += 1
                continue

            tm = TAB_CAP_RE.match(line)
            if tm:
                self.pending_table_caption = (tm.group(1).strip(), tm.group(2).strip())
                i += 1
                continue

            if line.startswith("|"):
                table_lines = []
                while i < len(self.lines) and self.lines[i].strip().startswith("|"):
                    table_lines.append(self.lines[i].strip())
                    i += 1
                self._add_table(table_lines)
                continue

            if line.startswith("```"):
                lang = line[3:].strip()
                code_lines = []
                i += 1
                while i < len(self.lines) and not self.lines[i].strip().startswith("```"):
                    code_lines.append(self.lines[i].rstrip("\n"))
                    i += 1
                i += 1
                self.blocks.append(Block("code", text="\n".join(code_lines), lang=lang))
                continue

            if line.startswith("- "):
                items = []
                while i < len(self.lines) and self.lines[i].strip().startswith("- "):
                    items.append(self.lines[i].strip()[2:].strip())
                    i += 1
                self.blocks.append(Block("bullets", items=items))
                continue

            nm = re.match(r"^\d+\.\s+(.*)$", line.strip())
            if nm:
                items = []
                while i < len(self.lines):
                    nm2 = re.match(r"^\d+\.\s+(.*)$", self.lines[i].strip())
                    if not nm2:
                        break
                    items.append(nm2.group(1).strip())
                    i += 1
                self.blocks.append(Block("numbers", items=items))
                continue

            if line.startswith("> "):
                quote_lines = []
                while i < len(self.lines) and self.lines[i].strip().startswith("> "):
                    quote_lines.append(self.lines[i].strip()[2:].strip())
                    i += 1
                self.blocks.append(Block("quote", text=" ".join(quote_lines)))
                continue

            # Paragraph: collect until a blank line or a special line.
            para = [line.strip()]
            i += 1
            while i < len(self.lines):
                nxt = self.lines[i].rstrip()
                if not nxt.strip():
                    break
                if nxt.startswith("#") or nxt.startswith("|") or nxt.startswith("```") \
                        or nxt.startswith("- ") or nxt.startswith("> ") or FIG_RE.match(nxt) \
                        or TAB_CAP_RE.match(nxt) or re.match(r"^\d+\.\s+", nxt.strip()):
                    break
                para.append(nxt.strip())
                i += 1
            self.blocks.append(Block("paragraph", text=" ".join(para)))

        if self.pending_table_caption is not None:
            self.errors.append("Table caption without a following table: " + self.pending_table_caption[1])

    def _add_table(self, lines: list[str]) -> None:
        rows: list[list[str]] = []
        for ln in lines:
            cells = [c.strip() for c in ln.strip().strip("|").split("|")]
            rows.append(cells)
        if len(rows) < 2:
            self.errors.append("Table has fewer than two rows: " + lines[0])
            return
        # Remove the separator row.
        clean: list[list[str]] = [rows[0]]
        for r in rows[1:]:
            if all(re.fullmatch(r":?-{2,}:?", c or "") for c in r):
                continue
            clean.append(r)
        headers, body = clean[0], clean[1:]
        if self.pending_table_caption is None:
            self.errors.append("Table without a caption: " + " | ".join(headers))
            cap, tid = "", "tab:untitled"
        else:
            cap, tid = self.pending_table_caption
            self.pending_table_caption = None
        if tid in self.tab_by_id:
            self.errors.append(f"Duplicate table id: {tid}")
        self.tab_no += 1
        label = f"Table {self.chapter_no}.{self.tab_no}"
        table = Table(tid, cap, label, headers, body)
        self.tables.append(table)
        self.tab_by_id[tid] = table
        self.blocks.append(Block("table", table=table))

    def resolve_tokens(self, text: str) -> str:
        def repl(m: re.Match[str]) -> str:
            kind, ident = m.group(1), m.group(2)
            key = kind + ":" + ident
            if kind == "fig":
                f = self.fig_by_id.get(key)
                if f is None:
                    self.errors.append(f"Unknown figure reference: {ident}")
                    return "Figure ?"
                return f.label
            t = self.tab_by_id.get(key)
            if t is None:
                self.errors.append(f"Unknown table reference: {ident}")
                return "Table ?"
            return t.label
        return TOKEN_RE.sub(repl, text)


def set_cell_shading(cell, hex_color: str) -> None:
    tcPr = cell._tc.get_or_add_tcPr()
    shd = OxmlElement("w:shd")
    shd.set(qn("w:val"), "clear")
    shd.set(qn("w:color"), "auto")
    shd.set(qn("w:fill"), hex_color)
    tcPr.append(shd)


def set_cell_margins(cell, top=40, start=70, bottom=40, end=70) -> None:
    tc = cell._tc
    tcPr = tc.get_or_add_tcPr()
    tcMar = tcPr.first_child_found_in("w:tcMar")
    if tcMar is None:
        tcMar = OxmlElement("w:tcMar")
        tcPr.append(tcMar)
    for tag, val in (("w:top", top), ("w:start", start), ("w:bottom", bottom), ("w:end", end)):
        node = tcMar.find(qn(tag))
        if node is None:
            node = OxmlElement(tag)
            tcMar.append(node)
        node.set(qn("w:w"), str(val))
        node.set(qn("w:type"), "dxa")


def set_repeat_table_header(row) -> None:
    trPr = row._tr.get_or_add_trPr()
    tblHeader = OxmlElement("w:tblHeader")
    tblHeader.set(qn("w:val"), "true")
    trPr.append(tblHeader)


def add_page_field(paragraph) -> None:
    run = paragraph.add_run()
    fld1 = OxmlElement("w:fldChar")
    fld1.set(qn("w:fldCharType"), "begin")
    instr = OxmlElement("w:instrText")
    instr.set(qn("xml:space"), "preserve")
    instr.text = " PAGE "
    fld2 = OxmlElement("w:fldChar")
    fld2.set(qn("w:fldCharType"), "separate")
    txt = OxmlElement("w:t")
    txt.text = "1"
    fld3 = OxmlElement("w:fldChar")
    fld3.set(qn("w:fldCharType"), "end")
    run._r.append(fld1)
    run._r.append(instr)
    run._r.append(fld2)
    run._r.append(txt)
    run._r.append(fld3)


def add_tab_leader(paragraph, pos_cm: float = 15.4) -> None:
    pPr = paragraph._p.get_or_add_pPr()
    tabs = OxmlElement("w:tabs")
    tab = OxmlElement("w:tab")
    tab.set(qn("w:val"), "right")
    tab.set(qn("w:leader"), "dot")
    tab.set(qn("w:pos"), str(int(pos_cm * 567)))
    tabs.append(tab)
    pPr.append(tabs)


def add_right_tab(paragraph, pos_cm: float = 15.2) -> None:
    pPr = paragraph._p.get_or_add_pPr()
    tabs = OxmlElement("w:tabs")
    tab = OxmlElement("w:tab")
    tab.set(qn("w:val"), "right")
    tab.set(qn("w:pos"), str(int(pos_cm * 567)))
    tabs.append(tab)
    pPr.append(tabs)


def add_bottom_border(paragraph, color="808080", size=4) -> None:
    pPr = paragraph._p.get_or_add_pPr()
    pBdr = OxmlElement("w:pBdr")
    bottom = OxmlElement("w:bottom")
    bottom.set(qn("w:val"), "single")
    bottom.set(qn("w:sz"), str(size))
    bottom.set(qn("w:space"), "1")
    bottom.set(qn("w:color"), color)
    pBdr.append(bottom)
    pPr.append(pBdr)


def add_run(paragraph, text: str, bold=False, italic=False, code=False, size=None, color=None):
    run = paragraph.add_run(text)
    run.font.name = CODE_FONT if code else BODY_FONT
    run.font.size = size or (Pt(10) if code else BODY_SIZE)
    run.bold = bold
    run.italic = italic
    if color is not None:
        run.font.color.rgb = color
    if code:
        run.font.name = CODE_FONT
        rPr = run._element.get_or_add_rPr()
        rFonts = rPr.find(qn("w:rFonts"))
        if rFonts is None:
            rFonts = OxmlElement("w:rFonts")
            rPr.append(rFonts)
        rFonts.set(qn("w:ascii"), CODE_FONT)
        rFonts.set(qn("w:hAnsi"), CODE_FONT)
        rFonts.set(qn("w:cs"), CODE_FONT)
    return run


def add_inline(paragraph, text: str, size=None, color=None, allow_code: bool = True) -> None:
    pos = 0
    for m in INLINE_RE.finditer(text):
        if m.start() > pos:
            add_run(paragraph, text[pos:m.start()], size=size, color=color)
        token = m.group(0)
        if token.startswith("**") and token.endswith("**"):
            add_run(paragraph, token[2:-2], bold=True, size=size, color=color)
        elif token.startswith("`") and token.endswith("`"):
            # All prose, including inline code, follows the TNR 12 rule.
            # Code blocks remain the only monospaced exception.
            add_run(paragraph, token[1:-1], italic=True, size=size, color=color)
        elif token.startswith("*") and token.endswith("*"):
            add_run(paragraph, token[1:-1], italic=True, size=size, color=color)
        else:
            add_run(paragraph, token, size=size, color=color)
        pos = m.end()
    if pos < len(text):
        add_run(paragraph, text[pos:], size=size, color=color)


class ManualBuilder:
    def __init__(self, parser: ManualParser, page_map: dict[str, str] | None = None):
        self.p = parser
        self.page_map = page_map or {}
        self.doc = Document()
        self._setup_styles()
        self._setup_section()

    def _setup_styles(self) -> None:
        styles = self.doc.styles
        normal = styles["Normal"]
        normal.font.name = BODY_FONT
        normal.font.size = BODY_SIZE
        normal.paragraph_format.line_spacing = 1.5
        normal.paragraph_format.space_after = Pt(4)
        normal.paragraph_format.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
        # East Asian font mapping so Word does not substitute.
        rPr = normal.element.get_or_add_rPr()
        rFonts = rPr.find(qn("w:rFonts"))
        if rFonts is None:
            rFonts = OxmlElement("w:rFonts")
            rPr.append(rFonts)
        for attr in ("w:ascii", "w:hAnsi", "w:cs", "w:eastAsia"):
            rFonts.set(qn(attr), BODY_FONT)

        h1 = styles["Heading 1"]
        h1.font.name = BODY_FONT
        h1.font.size = Pt(12)
        h1.font.bold = True
        h1.font.color.rgb = RGBColor(0, 0, 0)
        h1.paragraph_format.alignment = WD_ALIGN_PARAGRAPH.CENTER
        h1.paragraph_format.space_before = Pt(0)
        h1.paragraph_format.space_after = Pt(12)
        h1.paragraph_format.keep_with_next = True
        h1.paragraph_format.page_break_before = False
        h1.paragraph_format.line_spacing = 1.5

        h2 = styles["Heading 2"]
        h2.font.name = BODY_FONT
        h2.font.size = Pt(12)
        h2.font.bold = True
        h2.font.color.rgb = RGBColor(0, 0, 0)
        h2.paragraph_format.space_before = Pt(12)
        h2.paragraph_format.space_after = Pt(6)
        h2.paragraph_format.keep_with_next = True
        h2.paragraph_format.line_spacing = 1.5

        h3 = styles["Heading 3"]
        h3.font.name = BODY_FONT
        h3.font.size = Pt(12)
        h3.font.bold = True
        h3.font.color.rgb = RGBColor(0, 0, 0)
        h3.paragraph_format.space_before = Pt(10)
        h3.paragraph_format.space_after = Pt(4)
        h3.paragraph_format.keep_with_next = True

        for style_name in ("List Bullet", "List Number"):
            st = styles[style_name]
            st.font.name = BODY_FONT
            st.font.size = BODY_SIZE
            st.paragraph_format.line_spacing = 1.5
            st.paragraph_format.space_after = Pt(3)

    def _setup_section(self) -> None:
        section = self.doc.sections[0]
        section.page_width = Cm(21.59)
        section.page_height = Cm(27.94)
        section.top_margin = Cm(2.5)
        section.bottom_margin = Cm(2.5)
        section.left_margin = Cm(2.5)
        section.right_margin = Cm(2.5)
        section.header_distance = Cm(1.25)
        section.footer_distance = Cm(1.25)
        section.different_first_page_header_footer = False

        # The manual is intended to be merged into the capstone paper. Page
        # headers/footers are intentionally left empty so the paper's own
        # running header and pagination remain authoritative.
        for part in (section.header, section.footer, section.first_page_header, section.first_page_footer):
            for p in part.paragraphs:
                p.text = ""
            for table in part.tables:
                table._tbl.getparent().remove(table._tbl)

    def _page(self, key: str) -> str:
        return self.page_map.get(key, "00")

    def build(self) -> Document:
        self._title_page()
        self._toc()
        self._list_of_figures()
        self._list_of_tables()
        self._body()
        self._add_document_properties()
        return self.doc

    def _title_page(self) -> None:
        # Cover page: website emblem with the game icon badge, the SandEE
        # wordmark flanked by the Py-San and LUA sprites, and the capstone
        # subtitle. No administrative or version text.
        for _ in range(8):
            self.doc.add_paragraph()

        p = self.doc.add_paragraph()
        p.alignment = WD_ALIGN_PARAGRAPH.CENTER
        p.paragraph_format.space_before = Pt(6)
        p.paragraph_format.space_after = Pt(18)
        p.add_run().add_picture(str(DOCS / "manual_assets" / "cover" / "cover_emblem.png"), width=Cm(5.4))

        t = self.doc.add_table(rows=1, cols=3)
        t.alignment = WD_TABLE_ALIGNMENT.CENTER
        t.autofit = False
        for ci, w in enumerate((3.0, 9.4, 3.0)):
            t.columns[ci].width = Cm(w)
            for cell in t.columns[ci].cells:
                cell.width = Cm(w)
        for cell in t.rows[0].cells:
            set_cell_margins(cell, top=0, start=0, bottom=0, end=0)
            cell.vertical_alignment = WD_ALIGN_VERTICAL.CENTER

        left = t.rows[0].cells[0].paragraphs[0]
        left.alignment = WD_ALIGN_PARAGRAPH.CENTER
        left.add_run().add_picture(str(DOCS / "manual_assets" / "cover" / "pysan_sprite.png"), width=Cm(2.25))

        middle = t.rows[0].cells[1].paragraphs[0]
        middle.alignment = WD_ALIGN_PARAGRAPH.CENTER
        r = middle.add_run("SandEE")
        r.font.name = BODY_FONT
        r.font.size = Pt(48)
        r.bold = True

        right = t.rows[0].cells[2].paragraphs[0]
        right.alignment = WD_ALIGN_PARAGRAPH.CENTER
        right.add_run().add_picture(str(DOCS / "manual_assets" / "cover" / "lua_sprite.png"), width=Cm(1.2))

        p = self.doc.add_paragraph()
        p.alignment = WD_ALIGN_PARAGRAPH.CENTER
        p.paragraph_format.space_before = Pt(24)
        p.paragraph_format.space_after = Pt(6)
        r = p.add_run(SUBTITLE)
        r.font.name = BODY_FONT
        r.font.size = Pt(14)
        r.bold = False
        r.italic = True

    def _toc(self) -> None:
        p = self.doc.add_paragraph()
        p.paragraph_format.page_break_before = True
        p.alignment = WD_ALIGN_PARAGRAPH.CENTER
        r = p.add_run("TABLE OF CONTENTS")
        r.font.name = BODY_FONT
        r.font.size = Pt(12)
        r.bold = True
        p.paragraph_format.space_after = Pt(12)

        for h in self.p.headings:
            if h.text in ("Table of Contents", "List of Figures", "List of Tables"):
                continue
            p = self.doc.add_paragraph()
            p.paragraph_format.space_after = Pt(1.5)
            p.paragraph_format.line_spacing = 1.0
            if h.level == 1:
                p.paragraph_format.left_indent = Cm(0)
                add_run(p, h.text, size=Pt(12))
            elif h.level == 2:
                p.paragraph_format.left_indent = Cm(0.7)
                add_run(p, h.text, size=Pt(12))
            else:
                continue
            add_right_tab(p, 15.2)
            p.add_run("\t")
            add_run(p, self._page("h:" + h.text), size=Pt(12))

    def _list_of_figures(self) -> None:
        p = self.doc.add_paragraph()
        p.paragraph_format.page_break_before = True
        p.alignment = WD_ALIGN_PARAGRAPH.CENTER
        r = p.add_run("LIST OF FIGURES")
        r.font.name = BODY_FONT
        r.font.size = Pt(12)
        r.bold = True
        p.paragraph_format.space_after = Pt(12)

        for f in self.p.figures:
            p = self.doc.add_paragraph()
            p.paragraph_format.space_after = Pt(1.5)
            p.paragraph_format.line_spacing = 1.0
            p.paragraph_format.left_indent = Cm(1.2)
            p.paragraph_format.first_line_indent = Cm(-1.2)
            add_run(p, f"{f.label}. ", size=Pt(12))
            add_run(p, f.caption, size=Pt(12))
            add_right_tab(p, 15.2)
            p.add_run("\t")
            add_run(p, self._page("f:" + f.label), size=Pt(12))

    def _list_of_tables(self) -> None:
        p = self.doc.add_paragraph()
        p.paragraph_format.page_break_before = True
        p.alignment = WD_ALIGN_PARAGRAPH.CENTER
        r = p.add_run("LIST OF TABLES")
        r.font.name = BODY_FONT
        r.font.size = Pt(12)
        r.bold = True
        p.paragraph_format.space_after = Pt(12)

        for t in self.p.tables:
            p = self.doc.add_paragraph()
            p.paragraph_format.space_after = Pt(1.5)
            p.paragraph_format.line_spacing = 1.0
            p.paragraph_format.left_indent = Cm(1.2)
            p.paragraph_format.first_line_indent = Cm(-1.2)
            add_run(p, f"{t.label}. ", size=Pt(12))
            add_run(p, t.caption, size=Pt(12))
            add_right_tab(p, 15.2)
            p.add_run("\t")
            add_run(p, self._page("t:" + t.label), size=Pt(12))

    def _body(self) -> None:
        for block in self.p.blocks:
            if block.kind == "heading":
                text = block.text
                if block.level == 1:
                    p = self.doc.add_heading(level=1)
                    if text.strip() in ("Abstract", "Chapter 1. Introduction"):
                        p.paragraph_format.page_break_before = True
                    r = add_run(p, text, bold=True, size=Pt(12))
                    r.font.all_caps = True
                elif block.level == 2:
                    p = self.doc.add_heading(level=2)
                    add_run(p, text, bold=True, size=Pt(12))
                else:
                    p = self.doc.add_heading(level=3)
                    add_run(p, text, bold=True, size=Pt(12))
            elif block.kind == "paragraph":
                text = self.p.resolve_tokens(block.text)
                p = self.doc.add_paragraph()
                add_inline(p, text)
            elif block.kind == "figure":
                self._figure(block.figure)
            elif block.kind == "table":
                self._table(block.table)
            elif block.kind == "code":
                self._code(block.text)
            elif block.kind == "bullets":
                for item in block.items:
                    p = self.doc.add_paragraph(style="List Bullet")
                    add_inline(p, self.p.resolve_tokens(item))
            elif block.kind == "numbers":
                for item in block.items:
                    p = self.doc.add_paragraph(style="List Number")
                    add_inline(p, self.p.resolve_tokens(item))
            elif block.kind == "quote":
                p = self.doc.add_paragraph()
                p.paragraph_format.left_indent = Cm(1.0)
                p.paragraph_format.right_indent = Cm(1.0)
                p.paragraph_format.space_before = Pt(6)
                p.paragraph_format.space_after = Pt(8)
                add_inline(p, self.p.resolve_tokens(block.text), size=Pt(10.5), color=RGBColor(70, 70, 70))

    def _figure(self, fig: Figure) -> None:
        path = DOCS / fig.path
        p = self.doc.add_paragraph()
        p.alignment = WD_ALIGN_PARAGRAPH.CENTER
        p.paragraph_format.space_before = Pt(8)
        p.paragraph_format.space_after = Pt(3)
        p.paragraph_format.keep_with_next = True
        run = p.add_run()
        run.add_picture(str(path), width=Cm(12.0))

        cap = self.doc.add_paragraph()
        cap.alignment = WD_ALIGN_PARAGRAPH.CENTER
        cap.paragraph_format.space_after = Pt(6)
        cap.paragraph_format.line_spacing = 1.0
        add_run(cap, f"{fig.label}. ", bold=True, size=CAPTION_SIZE)
        add_inline(cap, fig.caption, size=CAPTION_SIZE)
        # Ensure the caption ends with a period unless it already ends with punctuation.
        if not cap.text.rstrip().endswith((".", "?", "!")):
            add_run(cap, ".", size=CAPTION_SIZE)

    def _table_widths(self, table: Table) -> list[float]:
        h = [x.strip() for x in table.headers]
        n = len(h)
        total = 15.3
        if n == 2:
            return [4.4, 10.9]
        if n == 3:
            return [3.6, 4.9, 6.8]
        if n == 5:
            return [2.9, 3.0, 2.8, 3.4, 3.2]
        if n == 6:
            return [2.55] * 6
        # Four-column tables: tailor the common shapes.
        if h and h[0] in ("Action", "Symptom", "Condition", "Event"):
            return [4.0, 3.6, 3.0, 4.7]
        if h and h[0].startswith("Function"):
            return [3.7, 3.6, 3.6, 4.4]
        if h and h[0] in ("Function and syntax", "Name and syntax"):
            return [3.7, 3.6, 3.6, 4.4]
        if h and h[0] == "Control":
            return [3.2, 4.0, 4.0, 4.1]
        if h and h[0] == "Setting":
            return [3.8, 2.2, 2.4, 3.8, 3.1] if n == 5 else [3.9, 3.9, 3.4, 4.1]
        if h and h[0] == "Property":
            return [3.6, 5.6, 6.1]
        # Default: equal widths with a little extra for the last column.
        base = total / n
        return [base] * n

    def _table(self, table: Table) -> None:
        cap = self.doc.add_paragraph()
        cap.paragraph_format.space_before = Pt(8)
        cap.paragraph_format.space_after = Pt(3)
        cap.paragraph_format.keep_with_next = True
        add_run(cap, f"{table.label}. ", bold=True, size=Pt(12))
        add_inline(cap, self.p.resolve_tokens(table.caption), size=Pt(12), allow_code=False)

        rows = len(table.rows) + 1
        cols = len(table.headers)
        t = self.doc.add_table(rows=rows, cols=cols)
        t.style = "Table Grid"
        t.alignment = WD_TABLE_ALIGNMENT.CENTER
        t.autofit = False
        widths = self._table_widths(table)
        # Force a fixed layout so Word/LibreOffice honour the widths.
        tblPr = t._tbl.tblPr
        layout = OxmlElement("w:tblLayout")
        layout.set(qn("w:type"), "fixed")
        tblPr.append(layout)
        for ci, w in enumerate(widths):
            t.columns[ci].width = Cm(w)
            for cell in t.columns[ci].cells:
                cell.width = Cm(w)
        # Header
        for c, text in enumerate(table.headers):
            cell = t.rows[0].cells[c]
            set_cell_shading(cell, "D9E2F3")
            set_cell_margins(cell, top=20, start=60, bottom=20, end=60)
            p = cell.paragraphs[0]
            p.alignment = WD_ALIGN_PARAGRAPH.LEFT
            p.paragraph_format.space_after = Pt(0)
            p.paragraph_format.line_spacing = 1.0
            p.paragraph_format.keep_with_next = True
            add_inline(p, text, size=TABLE_FONT_SIZE, allow_code=False)
            for r in p.runs:
                r.bold = True
        set_repeat_table_header(t.rows[0])
        # Body
        for ri, row in enumerate(table.rows, start=1):
            for ci in range(cols):
                cell = t.rows[ri].cells[ci]
                set_cell_margins(cell, top=20, start=60, bottom=20, end=60)
                p = cell.paragraphs[0]
                p.alignment = WD_ALIGN_PARAGRAPH.LEFT
                p.paragraph_format.space_after = Pt(0)
                p.paragraph_format.line_spacing = 1.0
                val = row[ci] if ci < len(row) else ""
                add_inline(p, self.p.resolve_tokens(val), size=TABLE_FONT_SIZE, allow_code=False)
        # Slightly tighter table row spacing.
        for row in t.rows:
            trPr = row._tr.get_or_add_trPr()
            cantSplit = OxmlElement("w:cantSplit")
            trPr.append(cantSplit)
        sp = self.doc.add_paragraph()
        sp.paragraph_format.space_after = Pt(4)
        sp.paragraph_format.line_spacing = 1.0

    def _code(self, text: str) -> None:
        p = self.doc.add_paragraph()
        p.alignment = WD_ALIGN_PARAGRAPH.LEFT
        p.paragraph_format.left_indent = Cm(0.5)
        p.paragraph_format.right_indent = Cm(0.5)
        p.paragraph_format.space_before = Pt(6)
        p.paragraph_format.space_after = Pt(8)
        p.paragraph_format.line_spacing = 1.0
        p.paragraph_format.keep_together = True
        # Shading
        pPr = p._p.get_or_add_pPr()
        shd = OxmlElement("w:shd")
        shd.set(qn("w:val"), "clear")
        shd.set(qn("w:color"), "auto")
        shd.set(qn("w:fill"), "F2F2F2")
        pPr.append(shd)
        # Border
        pBdr = OxmlElement("w:pBdr")
        for edge in ("top", "left", "bottom", "right"):
            el = OxmlElement(f"w:{edge}")
            el.set(qn("w:val"), "single")
            el.set(qn("w:sz"), "4")
            el.set(qn("w:space"), "4")
            el.set(qn("w:color"), "BFBFBF")
            pBdr.append(el)
        pPr.append(pBdr)

        lines = text.split("\n")
        for idx, line in enumerate(lines):
            if idx > 0:
                p.add_run().add_break(WD_BREAK.LINE)
            run = add_run(p, line if line else " ", code=True, size=CODE_SIZE)
            run.font.name = CODE_FONT
        # Add a language-free caption? Code examples are self-explanatory in the prose.

    def _add_document_properties(self) -> None:
        props = self.doc.core_properties
        props.title = "SandEE User Manual"
        props.subject = "SandEE user manual"
        props.author = "SandEE"
        props.comments = "SandEE user manual."
        props.category = "User manual"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--pages", default="", help="JSON page map produced from the first PDF pass")
    args = ap.parse_args()

    if not MD_PATH.exists():
        print(f"ERROR: missing {MD_PATH}", file=sys.stderr)
        return 2
    parser = ManualParser(MD_PATH)
    parser.parse()
    if parser.errors:
        print("PARSE ERRORS:", file=sys.stderr)
        for e in parser.errors:
            print(" -", e, file=sys.stderr)
        return 3

    page_map = {}
    if args.pages:
        page_map = json.loads(Path(args.pages).read_text(encoding="utf-8"))

    builder = ManualBuilder(parser, page_map)
    doc = builder.build()
    doc.save(DOCX_PATH)
    print(f"WROTE {DOCX_PATH}")
    print(f"FIGURES {len(parser.figures)} TABLES {len(parser.tables)} HEADINGS {len(parser.headings)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
