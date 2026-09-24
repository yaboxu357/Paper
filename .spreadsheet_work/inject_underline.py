#!/usr/bin/env python3
"""Inject the second-best underline into the generated workbook (all sheets).

`@oai/artifact-tool` accepts `format.font.underline` but never writes `<u/>`
into xl/styles.xml (verified against every documented spelling of the option),
so the underline is applied here at the OOXML level: one extra font and one
extra cell format are appended, and the ranked cells are re-pointed at them.
"""
import json
import re
import shutil
import zipfile
from pathlib import Path

ROOT = Path("C:/code/codexplace/paper")
XLSX = ROOT / "outputs/detailed-results/experiment_results_detailed.xlsx"
RANKS = ROOT / ".spreadsheet_work/detailed_rankings.json"

ranks = json.loads(RANKS.read_text(encoding="utf-8"))

with zipfile.ZipFile(XLSX) as zin:
    parts = {name: zin.read(name) for name in zin.namelist()}

# ---- map sheet name -> worksheet part -------------------------------------
workbook_xml = parts["xl/workbook.xml"].decode("utf-8")
rels_xml = parts["xl/_rels/workbook.xml.rels"].decode("utf-8")
relmap = {}
for m in re.finditer(r"<Relationship\b[^>]*/>", rels_xml):
    attrs = dict(re.findall(r'([\w:]+)="([^"]*)"', m.group(0)))
    relmap[attrs["Id"]] = attrs["Target"]
sheet_parts = {}
for m in re.finditer(r"<x:sheet\b[^>]*/>", workbook_xml):
    attrs = dict(re.findall(r'([\w:]+)="([^"]*)"', m.group(0)))
    target = relmap[attrs["r:id"]].lstrip("/")
    if not target.startswith("xl/"):
        target = "xl/" + target
    sheet_parts[attrs["name"]] = target
print("sheets:", sheet_parts)

# ---- append the underline font + cell format ------------------------------
styles = parts["xl/styles.xml"].decode("utf-8")
m = re.search(r'<x:fonts count="(\d+)">(.*?)</x:fonts>', styles, re.S)
font_count, fonts = int(m.group(1)), m.group(2)
UNDERLINE_FONT_ID = font_count
new_font = '<x:font><x:u /><x:sz val="10" /><x:color rgb="FF000000" /><x:name val="Times New Roman" /></x:font>'
styles = styles.replace(m.group(0), f'<x:fonts count="{font_count + 1}">{fonts}{new_font}</x:fonts>')

m = re.search(r'<x:cellXfs count="(\d+)">(.*?)</x:cellXfs>', styles, re.S)
xf_count, xfs = int(m.group(1)), m.group(2)


def split_xfs(text):
    """Split a cellXfs body into <x:xf> elements.

    A plain regex is unsafe here: `<x:xf ...><x:alignment /></x:xf>` contains a
    self-closing child, so a non-greedy match stops on the wrong `/>`.
    """
    out, i = [], 0
    while True:
        j = text.find("<x:xf ", i)
        if j < 0:
            return out
        gt = text.find(">", j)
        if text[gt - 1] == "/":
            out.append(text[j:gt + 1]); i = gt + 1
        else:
            e = text.find("</x:xf>", j); out.append(text[j:e + len("</x:xf>")]); i = e + len("</x:xf>")


xfs_list = split_xfs(xfs)
assert len(xfs_list) == xf_count, f"parsed {len(xfs_list)} xf elements, header says {xf_count}"
template = next(x for x in xfs_list if 'numFmtId="200"' in x and 'fontId="1"' in x and 'borderId="1"' in x)
new_xf = template.replace('fontId="1"', f'fontId="{UNDERLINE_FONT_ID}"')
UNDERLINE_XF_ID = xf_count
styles = styles.replace(m.group(0), f'<x:cellXfs count="{xf_count + 1}">{xfs}{new_xf}</x:cellXfs>')
parts["xl/styles.xml"] = styles.encode("utf-8")

# ---- re-point the second-best cells on each sheet -------------------------
for sheet_name, part in sheet_parts.items():
    second = set(ranks.get(f"{sheet_name}:addresses", {}).get("second", []))
    if not second:
        print(f"  {sheet_name}: no second-best cells")
        continue
    sheet = parts[part].decode("utf-8")
    changed = 0
    for addr in sorted(second):
        pattern = re.compile(r'(<x:c r="%s"(?:\s+s="\d+")?)' % re.escape(addr))
        match = pattern.search(sheet)
        if not match:
            print(f"  !! {sheet_name}: cell {addr} not found")
            continue
        sheet = (sheet[: match.start(1)] + re.sub(r'\s+s="\d+"', "", match.group(1))
                 + f' s="{UNDERLINE_XF_ID}"' + sheet[match.end(1):])
        changed += 1
    parts[part] = sheet.encode("utf-8")
    print(f"  {sheet_name}: {changed}/{len(second)} cells re-pointed at style {UNDERLINE_XF_ID}")

tmp = XLSX.with_suffix(".tmp.xlsx")
with zipfile.ZipFile(tmp, "w", zipfile.ZIP_DEFLATED) as zout:
    for name, data in parts.items():
        zout.writestr(name, data)
shutil.move(tmp, XLSX)
print(f"rewritten {XLSX}")
