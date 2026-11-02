"""Refresh the front matter of the Word-edited SandEE manual.

The manual is maintained in Word after the initial Markdown build, so chapter
numbers and the page references in the Table of Contents, List of Figures and
List of Tables have to be kept in step with the edited DOCX.

Usage:
    python docs/refresh_front_matter.py --shift 3
    python docs/refresh_front_matter.py --pages-only

--shift N subtracts N from every chapter, section, figure and table number and
from every in-text reference to one.  --pages-only leaves the numbering alone
and only recomputes the three front-matter lists.

Page numbers come from a PDF exported by Microsoft Word, so they match the
pagination the reader sees in Word.  LibreOffice is used only when Word is not
installed.
"""

from __future__ import annotations

import argparse
import copy
import os
import re
import shutil
import sys
import tempfile
import time
from pathlib import Path

from docx import Document
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.table import Table
from docx.text.paragraph import Paragraph

DOCS = Path(__file__).resolve().parent
DOCX = DOCS / "SandEE_User_Manual_Draft.docx"
PDF = DOCS / "SandEE_User_Manual_Draft.pdf"

W = "{http://schemas.openxmlformats.org/wordprocessingml/2006/main}"

TOC_TITLE = "TABLE OF CONTENTS"
LOF_TITLE = "LIST OF FIGURES"
LOT_TITLE = "LIST OF TABLES"

ABSTRACT_PROBE = "sandee is a two-dimensional sandbox game about"

CHAPTER_RE = re.compile(r"\b(Chapter) (\d+)\b")
CHAPTERS_RE = re.compile(r"\b(Chapters) (\d+) and (\d+)\b")
FIGURE_RE = re.compile(r"\b(Figure) (\d+)\.(\d+)\b")
TABLE_RE = re.compile(r"\b(Table) (\d+)\.(\d+)\b")
SECTION_RE = re.compile(r"^(\d+)\.(\d+)(?=\s)")
CAPTION_RE = re.compile(r"^(Figure|Table) (\d+)\.(\d+)\.\s")


# --------------------------------------------------------------------------
# Word helpers
# --------------------------------------------------------------------------


def export_pdf_word(path: Path, out: Path) -> bool:
    try:
        import win32com.client as win32
    except ImportError:
        return False

    if out.exists():
        out.unlink()
    word = win32.DispatchEx("Word.Application")
    word.Visible = False
    word.DisplayAlerts = 0
    try:
        doc = word.Documents.Open(str(path), ReadOnly=True, AddToRecentFiles=False)
        doc.ExportAsFixedFormat(
            OutputFileName=str(out),
            ExportFormat=17,  # wdExportFormatPDF
            OpenAfterExport=False,
            OptimizeFor=0,
            Range=0,
            Item=0,
            IncludeDocProps=True,
            KeepIRM=True,
            CreateBookmarks=0,
            DocStructureTags=True,
            BitmapMissingFonts=True,
            UseISO19005_1=False,
        )
        doc.Close(False)
        return True
    finally:
        try:
            word.Quit()
        except Exception:
            pass


def export_pdf_libreoffice(path: Path, out_dir: Path) -> bool:
    import subprocess

    soffice = Path(r"C:\Program Files\LibreOffice\program\soffice.exe")
    if not soffice.exists():
        return False
    subprocess.run(
        [str(soffice), "--headless", "--norestore", "--convert-to", "pdf", "--outdir", str(out_dir), str(path)],
        check=False,
        capture_output=True,
    )
    return (out_dir / (path.stem + ".pdf")).exists()


def export_pdf(path: Path, out: Path) -> None:
    if export_pdf_word(path, out):
        print("PDF exported with Word")
        return
    print("Word unavailable; falling back to LibreOffice")
    if not export_pdf_libreoffice(path, out.parent):
        raise SystemExit("Could not export the DOCX to PDF")
    built = out.parent / (path.stem + ".pdf")
    if built != out and built.exists():
        shutil.move(str(built), str(out))


# --------------------------------------------------------------------------
# Text renumbering
# --------------------------------------------------------------------------


def runs_and_offsets(paragraph: Paragraph):
    runs = paragraph.runs
    offsets = []
    pos = 0
    for run in runs:
        offsets.append((pos, pos + len(run.text), run))
        pos += len(run.text)
    return runs, offsets, pos


def replace_paragraph(paragraph: Paragraph, pattern: re.Pattern[str], repl) -> int:
    """Regex-replace across runs, preserving run formatting."""
    runs, offsets, total = runs_and_offsets(paragraph)
    if not runs or not total:
        return 0
    text = "".join(r.text for r in runs)
    matches = list(pattern.finditer(text))
    if not matches:
        return 0

    for match in reversed(matches):
        new = repl(match)
        start, end = match.start(), match.end()
        touched = [i for i, (a, b, _) in enumerate(offsets) if a < end and b > start]
        if not touched:
            continue
        first, last = touched[0], touched[-1]
        a0, b0, r0 = offsets[first]
        a1, b1, r1 = offsets[last]
        if first == last:
            r0.text = r0.text[: start - a0] + new + r0.text[end - a0 :]
        else:
            r0.text = r0.text[: start - a0] + new
            for i in range(first + 1, last):
                offsets[i][2].text = ""
            r1.text = r1.text[end - a1 :]
    return len(matches)


def shift_text(paragraph: Paragraph, shift: int, heading: bool) -> int:
    total = 0
    total += replace_paragraph(
        paragraph,
        CHAPTERS_RE,
        lambda m: f"{m.group(1)} {int(m.group(2)) - shift} and {int(m.group(3)) - shift}",
    )
    total += replace_paragraph(
        paragraph, CHAPTER_RE, lambda m: f"{m.group(1)} {int(m.group(2)) - shift}"
    )
    total += replace_paragraph(
        paragraph, FIGURE_RE, lambda m: f"{m.group(1)} {int(m.group(2)) - shift}.{m.group(3)}"
    )
    total += replace_paragraph(
        paragraph, TABLE_RE, lambda m: f"{m.group(1)} {int(m.group(2)) - shift}.{m.group(3)}"
    )
    if heading:
        total += replace_paragraph(
            paragraph, SECTION_RE, lambda m: f"{int(m.group(1)) - shift}.{m.group(2)}"
        )
    return total


# --------------------------------------------------------------------------
# Document walking
# --------------------------------------------------------------------------


def body_paragraphs(doc: Document) -> list[Paragraph]:
    return [
        Paragraph(child, doc)
        for child in doc.element.body.iterchildren()
        if child.tag == qn("w:p")
    ]


def all_paragraphs(doc: Document):
    for child in doc.element.body.iterchildren():
        if child.tag == qn("w:p"):
            yield Paragraph(child, doc)
        elif child.tag == qn("w:tbl"):
            for row in Table(child, doc).rows:
                for cell in row.cells:
                    for paragraph in cell.paragraphs:
                        yield paragraph


def is_heading(paragraph: Paragraph) -> bool:
    style = paragraph.style.name if paragraph.style is not None else ""
    return style.startswith("Heading")


def is_caption(paragraph: Paragraph) -> bool:
    text = paragraph.text.strip()
    if not CAPTION_RE.match(text):
        return False
    return bool(paragraph.runs) and bool(paragraph.runs[0].bold)


def clear_runs(paragraph: Paragraph) -> None:
    for child in list(paragraph._p):
        if child.tag in (qn("w:r"), qn("w:hyperlink"), qn("w:bookmarkStart"), qn("w:bookmarkEnd")):
            paragraph._p.remove(child)


def set_entry(paragraph: Paragraph, text: str, page: str) -> None:
    clear_runs(paragraph)
    paragraph.add_run(text)
    paragraph.add_run("\t" + page)


# --------------------------------------------------------------------------
# Page mapping
# --------------------------------------------------------------------------


def normalise(text: str) -> str:
    return re.sub(r"\s+", " ", text).strip()


def page_map(pdf_path: Path, headings: list[str], figures: list[str], tables: list[str]):
    import fitz

    document = fitz.open(pdf_path)
    raw = [page.get_text("text") for page in document]
    pages = [normalise(t).lower() for t in raw]
    lines = [[normalise(line).lower() for line in t.splitlines()] for t in raw]

    start = next((i for i, text in enumerate(pages) if ABSTRACT_PROBE in text), None)
    if start is None:
        raise SystemExit("Could not locate the start of the Abstract")

    cursor = start
    heading_pages: list[int] = []
    for heading in headings:
        needle = normalise(heading).lower()
        found = None
        for i in range(cursor, len(pages)):
            if needle in lines[i]:
                found = i
                break
        if found is None and len(needle) > 30:
            prefix = needle[:30]
            for i in range(cursor, len(pages)):
                if any(line.startswith(prefix) for line in lines[i]):
                    found = i
                    break
        if found is None:
            prefix = needle[:40]
            for i in range(cursor, len(pages)):
                if prefix in pages[i]:
                    found = i
                    break
        if found is None:
            raise SystemExit(f"Heading not found in PDF: {heading}")
        heading_pages.append(found + 1)
        cursor = found

    def captions(entries: list[str], from_page: int) -> list[int]:
        result = []
        cursor = from_page
        for entry in entries:
            needle = normalise(entry).lower()[:50]
            found = None
            for i in range(cursor, len(pages)):
                if needle in pages[i]:
                    found = i
                    break
            if found is None:
                raise SystemExit(f"Caption not found in PDF: {entry[:60]}")
            result.append(found + 1)
            cursor = found
        return result

    figure_pages = captions(figures, start)
    table_pages = captions(tables, start)
    return heading_pages, figure_pages, table_pages, len(pages)


# --------------------------------------------------------------------------
# Main
# --------------------------------------------------------------------------


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--shift", type=int, default=0, help="subtract this from chapter/section/figure/table numbers")
    parser.add_argument("--pages-only", action="store_true", help="only recompute page references")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    if not DOCX.exists():
        raise SystemExit(f"Missing {DOCX}")

    backup = DOCX.with_name(DOCX.name.replace(".docx", f".backup.docx"))
    shutil.copy2(DOCX, backup)
    print("Backup written to", backup)

    doc = Document(DOCX)
    paragraphs = body_paragraphs(doc)

    toc_index = next(i for i, p in enumerate(paragraphs) if p.text.strip() == TOC_TITLE)
    lof_index = next(i for i, p in enumerate(paragraphs) if p.text.strip() == LOF_TITLE)
    lot_index = next(i for i, p in enumerate(paragraphs) if p.text.strip() == LOT_TITLE)
    abstract_index = next(
        i
        for i, p in enumerate(paragraphs)
        if i > lot_index and is_heading(p) and p.text.strip() == "Abstract"
    )

    if args.shift and not args.pages_only:
        moved = 0
        for paragraph in all_paragraphs(doc):
            moved += shift_text(paragraph, args.shift, is_heading(paragraph))
        print(f"Renumbered {moved} references")

    paragraphs = body_paragraphs(doc)
    headings = [p.text.strip() for p in paragraphs[abstract_index:] if is_heading(p)]
    captions = [p for p in paragraphs[abstract_index:] if is_caption(p)]
    figures = [p.text.strip() for p in captions if p.text.strip().startswith("Figure ")]
    tables = [p.text.strip() for p in captions if p.text.strip().startswith("Table ")]

    toc_entries = paragraphs[toc_index + 1 : lof_index]
    lof_entries = paragraphs[lof_index + 1 : lot_index]
    lot_entries = paragraphs[lot_index + 1 : abstract_index]

    print(f"Headings {len(headings)}  Figures {len(figures)}  Tables {len(tables)}")
    print(f"TOC entries {len(toc_entries)}  LoF entries {len(lof_entries)}  LoT entries {len(lot_entries)}")

    if len(headings) != len(toc_entries):
        raise SystemExit("TOC entry count does not match the body; aborting")
    if len(figures) != len(lof_entries):
        raise SystemExit("Figure count does not match the body; aborting")
    if len(tables) != len(lot_entries):
        raise SystemExit("Table count does not match the body; aborting")

    if args.dry_run:
        print("DRY RUN - no files written")
        print("First headings:", headings[:4])
        print("First figures:", figures[:2])
        return 0

    if args.shift and not args.pages_only:
        doc.save(DOCX)

    for attempt in range(1, 4):
        export_pdf(DOCX, PDF)
        h_pages, f_pages, t_pages, total = page_map(PDF, headings, figures, tables)
        print(f"Pass {attempt}: {total} pages")

        for paragraph, text, page in zip(toc_entries, headings, h_pages):
            set_entry(paragraph, text, str(page))
        for paragraph, text, page in zip(lof_entries, figures, f_pages):
            set_entry(paragraph, text, str(page))
        for paragraph, text, page in zip(lot_entries, tables, t_pages):
            set_entry(paragraph, text, str(page))

        doc.save(DOCX)
        export_pdf(DOCX, PDF)
        h2, f2, t2, total2 = page_map(PDF, headings, figures, tables)
        if (h2, f2, t2) == (h_pages, f_pages, t_pages):
            print(f"Stable after pass {attempt}: {total2} pages")
            break
        print("Page numbers moved; repeating")
    else:
        raise SystemExit("Page references did not stabilise")

    print("Last TOC entries:")
    for paragraph in toc_entries[-4:]:
        print("  ", paragraph.text)
    print("Last LoF entries:")
    for paragraph in lof_entries[-3:]:
        print("  ", paragraph.text)
    print("Last LoT entries:")
    for paragraph in lot_entries[-3:]:
        print("  ", paragraph.text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
