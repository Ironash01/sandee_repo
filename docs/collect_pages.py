import json
import re
import sys
from pathlib import Path

import fitz

sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_manual import ManualParser, MD_PATH  # noqa: E402


def norm(s: str) -> str:
    return re.sub(r"\s+", " ", s).strip()


def main() -> int:
    pdf_path = Path(__file__).resolve().parent / "SandEE_User_Manual_Draft.pdf"
    doc = fitz.open(pdf_path)
    raw_pages = [p.get_text("text") for p in doc]
    pages = [norm(t) for t in raw_pages]
    print("PAGES", len(pages))

    parser = ManualParser(MD_PATH)
    parser.parse()
    if parser.errors:
        print("PARSE ERRORS", parser.errors)
        return 2

    page_map: dict[str, str] = {}

    def find_last(fragment: str) -> int | None:
        needle = norm(fragment).lower()
        hits = [i for i, text in enumerate(pages) if needle and needle in text.lower()]
        if not hits:
            # Try a shorter prefix for long headings/captions.
            if len(needle) > 40:
                short = needle[:40]
                hits = [i for i, text in enumerate(pages) if short in text.lower()]
        return (hits[-1] + 1) if hits else None

    def find_heading(fragment: str) -> int | None:
        needle = norm(fragment).lower()
        hits = []
        for i, text in enumerate(raw_pages):
            for line in text.splitlines():
                if norm(line).lower() == needle:
                    hits.append(i)
                    break
        if not hits:
            return find_last(fragment)
        return hits[-1] + 1

    for h in parser.headings:
        if h.text in ("Table of Contents", "List of Figures", "List of Tables"):
            continue
        page = find_heading(h.text)
        if page:
            page_map["h:" + h.text] = str(page)

    for f in parser.figures:
        page = find_last(f.caption[:45])
        if page:
            page_map["f:" + f.label] = str(page)

    for t in parser.tables:
        page = find_last(t.caption[:45])
        if page:
            page_map["t:" + t.label] = str(page)

    out = Path(__file__).resolve().parent / "pages.json"
    out.write_text(json.dumps(page_map, indent=2, ensure_ascii=False), encoding="utf-8")
    print("MAPPED", len(page_map), "->", out)

    missing_head = [h.text for h in parser.headings if h.text not in ("Table of Contents", "List of Figures", "List of Tables") and ("h:" + h.text) not in page_map]
    missing_fig = [f.label for f in parser.figures if ("f:" + f.label) not in page_map]
    missing_tab = [t.label for t in parser.tables if ("t:" + t.label) not in page_map]
    if missing_head:
        print("MISSING HEADINGS", len(missing_head), missing_head[:10])
    if missing_fig:
        print("MISSING FIGURES", len(missing_fig), missing_fig[:10])
    if missing_tab:
        print("MISSING TABLES", len(missing_tab), missing_tab[:10])
    print("FIRST PAGES")
    for i in range(min(6, len(pages))):
        print(i + 1, pages[i][:160].replace("\n", " "))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
