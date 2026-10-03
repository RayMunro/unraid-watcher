#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Ray Munro
"""Builds docs/Unraid-Watcher-Documentation.pdf from the markdown files.

Needs only Python 3 and Google Chrome (used headless to print the PDF).
Usage: python3 tools/make_docs_pdf.py [output.pdf]
"""
import base64, html, pathlib, re, subprocess, sys, tempfile, time

ROOT = pathlib.Path(__file__).resolve().parent.parent
VERSION = "1.1.0"
REPO = "https://github.com/RayMunro/unraid-watcher"
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

# (file, anchor id, title shown in the contents list)
CHAPTERS = [
    ("README.md", "overview", "Overview"),
    ("docs/getting-started.md", "getting-started", "Getting started"),
    ("docs/user-guide.md", "user-guide", "User guide"),
    ("docs/settings.md", "settings", "Settings"),
    ("docs/alerts.md", "alerts", "Alerts and notifications"),
    ("docs/controls-and-safety.md", "controls-and-safety", "Controls and safety"),
    ("docs/troubleshooting.md", "troubleshooting", "Troubleshooting"),
    ("docs/data-sources.md", "data-sources", "Data sources"),
    ("docs/architecture.md", "architecture", "Architecture"),
    ("docs/building-and-releasing.md", "building-and-releasing", "Building and releasing"),
    ("CHANGELOG.md", "changelog", "Changelog"),
]
ANCHORS = {pathlib.Path(f).name: a for f, a, _ in CHAPTERS}


def fix_link(url):
    if url.startswith(("http://", "https://", "mailto:")):
        return url
    name = pathlib.PurePosixPath(url.split("#")[0]).name
    if name in ANCHORS:
        return "#" + ANCHORS[name]
    if name == "LICENSE":
        return f"{REPO}/blob/main/LICENSE"
    return url


def inline(s):
    codes = []

    def stash(m):
        codes.append(m.group(1))
        return f"\x00{len(codes) - 1}\x00"

    s = re.sub(r"`([^`]+)`", stash, s)
    s = html.escape(s, quote=False)
    s = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", s)
    s = re.sub(r"\[([^\]]+)\]\(([^)\s]+)\)", lambda m: f'<a href="{fix_link(m.group(2))}">{m.group(1)}</a>', s)
    return re.sub(r"\x00(\d+)\x00", lambda m: "<code>" + html.escape(codes[int(m.group(1))], quote=False) + "</code>", s)


LIST_RE = re.compile(r"^(\s*)([-*]|\d+\.)\s+(.*)$")
FENCE_RE = re.compile(r"^(\s*)```")


def convert(md):
    lines = md.split("\n")
    out, para, stack = [], [], []   # stack of [tag, indent]
    i = 0

    def flush():
        if para:
            out.append("<p>" + inline(" ".join(para)) + "</p>")
            para.clear()

    def close_lists(to=-1):
        while stack and stack[-1][1] > to:
            out.append(f"</li></{stack.pop()[0]}>")

    while i < len(lines):
        line = lines[i]
        fm = FENCE_RE.match(line)
        if fm:
            flush()
            if not fm.group(1):
                close_lists()
            indent = len(fm.group(1))
            i += 1
            code = []
            while i < len(lines) and not FENCE_RE.match(lines[i]):
                code.append(lines[i][indent:] if lines[i][:indent].strip() == "" else lines[i])
                i += 1
            out.append("<pre><code>" + html.escape("\n".join(code), quote=False) + "</code></pre>")
            i += 1
            continue
        if not line.strip():
            flush()
            i += 1
            continue
        lm = LIST_RE.match(line)
        if lm:
            flush()
            indent, marker, text = len(lm.group(1)), lm.group(2), lm.group(3)
            tag = "ol" if marker[0].isdigit() else "ul"
            if not stack or indent > stack[-1][1]:
                out.append(f"<{tag}><li>{inline(text)}")
                stack.append([tag, indent])
            else:
                close_lists(indent)
                if stack and stack[-1][1] == indent:
                    out.append(f"</li><li>{inline(text)}")
                else:
                    out.append(f"<{tag}><li>{inline(text)}")
                    stack.append([tag, indent])
            i += 1
            continue
        if stack and line.startswith(" "):          # continuation of a list item
            out.append(" " + inline(line.strip()))
            i += 1
            continue
        close_lists()
        hm = re.match(r"^(#{1,6})\s+(.*)$", line)
        if hm:
            flush()
            n = len(hm.group(1))
            out.append(f"<h{n}>{inline(hm.group(2))}</h{n}>")
            i += 1
            continue
        if line.startswith("|"):
            flush()
            rows = []
            while i < len(lines) and lines[i].startswith("|"):
                rows.append([c.strip() for c in lines[i].strip().strip("|").split("|")])
                i += 1
            head, body = rows[0], [r for r in rows[2:]] if len(rows) > 1 and set("".join(rows[1])) <= set("-: ") else rows[1:]
            t = "<table><thead><tr>" + "".join(f"<th>{inline(c)}</th>" for c in head) + "</tr></thead><tbody>"
            for r in body:
                t += "<tr>" + "".join(f"<td>{inline(c)}</td>" for c in r) + "</tr>"
            out.append(t + "</tbody></table>")
            continue
        if re.match(r"^-{3,}$", line.strip()):
            flush()
            out.append("<hr>")
            i += 1
            continue
        if line.startswith("<"):
            flush()
            out.append(line)
            i += 1
            continue
        para.append(line.strip())
        i += 1
    flush()
    close_lists()
    return "\n".join(out)


CSS = """
@page { size: A4; margin: 22mm 18mm 24mm;
  @bottom-left { content: "Unraid Watcher  \\00B7  Page " counter(page); }
  @bottom-center { content: none; }
  @bottom-right { content: "\\00A9  2026 Ray Munro"; } }
@page cover { margin: 0; @bottom-left { content: none; } @bottom-right { content: none; } }
@page { @bottom-left { font: 9pt -apple-system, 'Helvetica Neue', sans-serif; color: #888; }
        @bottom-right { font: 9pt -apple-system, 'Helvetica Neue', sans-serif; color: #888; } }
* { box-sizing: border-box; }
body { font: 10.5pt/1.5 -apple-system, 'Helvetica Neue', Helvetica, Arial, sans-serif; color: #1d2430; margin: 0; }
.cover { page: cover; height: 297mm; text-align: center; color: #fff; padding-top: 62mm;
  background: linear-gradient(180deg, #0a1530 0%, #123a5e 55%, #1b7f8e 100%); page-break-after: always; }
.cover img { width: 62mm; height: 62mm; filter: drop-shadow(0 6px 14px rgba(0,0,0,.45)); }
.cover h1 { font-size: 34pt; margin: 14mm 0 2mm; letter-spacing: .3pt; border: 0; color: #fff; }
.cover .sub { font-size: 16pt; opacity: .9; margin: 0 0 10mm; }
.cover .meta { font-size: 11pt; opacity: .8; margin: 0 0 40mm; }
.cover .copy { font-size: 10.5pt; opacity: .85; line-height: 1.6; }
.cover .src { font-size: 9pt; opacity: .7; }
.toc { page-break-after: always; }
.toc ol { line-height: 2; font-size: 11.5pt; }
.chapter { page-break-before: always; }
.toc + .chapter { page-break-before: auto; }
h1 { font-size: 22pt; color: #0f3a5c; border-bottom: 2px solid #1b7f8e; padding-bottom: 4pt; margin-top: 0; }
h2 { font-size: 15pt; color: #0f3a5c; margin-top: 20pt; break-after: avoid; }
h3 { font-size: 12pt; color: #1b5f78; margin-top: 14pt; break-after: avoid; }
h4 { font-size: 11pt; break-after: avoid; }
p, li { orphans: 3; widows: 3; }
a { color: #1566a8; text-decoration: none; }
code { font: 9pt ui-monospace, Menlo, monospace; background: #eef2f6; padding: 1pt 3pt; border-radius: 3pt; }
pre { background: #f2f5f8; border: 1px solid #dde4ec; border-radius: 6pt; padding: 8pt 10pt; white-space: pre-wrap;
  word-break: break-word; break-inside: avoid; }
pre code { background: none; padding: 0; font-size: 8.6pt; line-height: 1.4; }
table { border-collapse: collapse; width: 100%; margin: 8pt 0 12pt; font-size: 9.5pt; break-inside: auto; }
tr { break-inside: avoid; }
th { background: #e6eef5; text-align: left; }
th, td { border: 1px solid #ccd6e0; padding: 4pt 7pt; vertical-align: top; }
tr:nth-child(even) td { background: #f8fafc; }
hr { border: 0; border-top: 1px solid #ccd6e0; }
.chapter > p[align=center] { display: none; }   /* the cover carries the icon */
"""


def build(out_pdf):
    icon = base64.b64encode((ROOT / "docs/assets/icon.png").read_bytes()).decode()
    parts = [
        f'<section class="cover"><img src="data:image/png;base64,{icon}" alt="Unraid Watcher icon">'
        f"<h1>Unraid Watcher</h1><p class=\"sub\">Documentation</p><p class=\"meta\">Version {VERSION}</p>"
        f'<p class="copy">© 2026 Ray Munro<br>Licensed under the GNU General Public License v3.0 or later</p>'
        f'<p class="src">Source code: {REPO}</p></section>',
        '<section class="toc"><h1>Contents</h1><ol>'
        + "".join(f'<li><a href="#{a}">{t}</a></li>' for _, a, t in CHAPTERS) + "</ol></section>",
    ]
    for f, a, _ in CHAPTERS:
        parts.append(f'<section class="chapter" id="{a}">{convert((ROOT / f).read_text())}</section>')
    doc = f"<!doctype html><html><head><meta charset='utf-8'><title>Unraid Watcher Documentation</title><style>{CSS}</style></head><body>{''.join(parts)}</body></html>"
    with tempfile.TemporaryDirectory() as d:
        page = pathlib.Path(d) / "docs.html"
        page.write_text(doc, encoding="utf-8")
        out = pathlib.Path(out_pdf)
        out.unlink(missing_ok=True)
        proc = subprocess.Popen([CHROME, "--headless=new", "--disable-gpu", "--no-pdf-header-footer",
                                 f"--user-data-dir={d}/profile", f"--print-to-pdf={out_pdf}", page.as_uri()],
                                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        # Chrome writes the PDF and may then linger, so wait for a stable file and close it ourselves.
        last, stable, waited = -1, 0, 0.0
        while waited < 90:
            time.sleep(0.5); waited += 0.5
            size = out.stat().st_size if out.exists() else -1
            stable = stable + 1 if size > 0 and size == last else 0
            last = size
            if stable >= 3 or proc.poll() is not None and size > 0:
                break
        proc.terminate()
        try:
            proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            proc.kill()
        if not out.exists() or out.stat().st_size == 0:
            sys.exit("Chrome did not produce a PDF")
    print(f"Wrote {out_pdf} ({pathlib.Path(out_pdf).stat().st_size // 1024} KB)")


if __name__ == "__main__":
    build(sys.argv[1] if len(sys.argv) > 1 else str(ROOT / "docs/Unraid-Watcher-Documentation.pdf"))
