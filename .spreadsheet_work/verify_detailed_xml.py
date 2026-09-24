#!/usr/bin/env python3
"""Standards-level check of the generated detailed table, straight from the OOXML parts."""
import json
import math
import re
import zipfile
from pathlib import Path

ROOT = Path("C:/code/codexplace/paper")
W = ROOT / ".spreadsheet_work"
XLSX = ROOT / "outputs/detailed-results/experiment_results_detailed.xlsx"

src = json.loads((W / "dump_results.txt").read_text(encoding="utf-8").split("=== SHEET Sheet1 ===")[1].strip())["values"]
z = zipfile.ZipFile(XLSX)
ss = [re.sub(r"<[^>]+>", "", s) for s in re.findall(r"<x:si>(.*?)</x:si>", z.read("xl/sharedStrings.xml").decode(), re.S)]
sheet = z.read("xl/worksheets/sheet1.xml").decode()
styles = z.read("xl/styles.xml").decode()
fonts = re.findall(r"<x:font[ >].*?</x:font>|<x:font ?/>", styles.split("<x:fonts")[1].split("</x:fonts>")[0], re.S)
xf_body = styles.split("<x:cellXfs")[1].split("</x:cellXfs>")[0]


def split_xfs(text):
    out, i = [], 0
    while True:
        j = text.find("<x:xf ", i)
        if j < 0:
            return out
        gt = text.find(">", j)
        if text[gt - 1] == "/":
            out.append(text[j:gt + 1]); i = gt + 1
        else:
            e = text.find("</x:xf>", j); out.append(text[j:e + 7]); i = e + 7


xfs = split_xfs(xf_body)
cells, cell_styles = {}, {}
for m in re.finditer(r'<x:c r="([A-Z]+\d+)"(?: s="(\d+)")?(?: t="(\w+)")?\s*(?:/>|>(.*?)</x:c>)', sheet, re.S):
    addr, sid, typ, inner = m.group(1), int(m.group(2) or 0), m.group(3), m.group(4)
    cell_styles[addr] = sid
    v = re.search(r"<x:v>(.*?)</x:v>", inner or "")
    if not v:
        cells[addr] = None
    else:
        cells[addr] = ss[int(v.group(1))] if typ == "s" else (v.group(1) if typ == "str" else float(v.group(1)))

trunc3 = lambda x: math.trunc((float(x) + 2.220446049250313e-16) * 1000) / 1000
models = [[2, 4], [6, 7], [8, 9], [10, 11], [12, 13], [14, 15], [16, 17], [18, 19], [20, 21], [22, 23], [24, 25]]
cols = "ABCDEFGHIJKLMNOPQRSTUVWX"

bad = checked = 0
for d in range(9):
    s0 = 2 + d * 5
    for h in range(4):
        r, srow = 3 + d * 5 + h, src[s0 + h]
        for mi, (mse, mae) in enumerate(models):
            for scol, outc in ((mse, 2 + mi * 2), (mae, 3 + mi * 2)):
                exp = trunc3(srow[scol]) if srow[scol] is not None else None
                got = cells.get(f"{cols[outc]}{r}")
                checked += 1
                if exp is None:
                    if got is not None:
                        bad += 1; print("BAD", cols[outc], r, got, "expected blank")
                elif got is None or abs(got - exp) > 1e-12:
                    bad += 1; print("BAD", cols[outc], r, "got", got, "want", exp)
    r = 3 + d * 5 + 4
    for mi, (mse, mae) in enumerate(models):
        for scol, outc in ((mse, 2 + mi * 2), (mae, 3 + mi * 2)):
            arr = [src[s0 + h][scol] for h in range(4) if src[s0 + h][scol] is not None]
            exp = trunc3(sum(arr) / 4) if len(arr) == 4 else None
            got = cells.get(f"{cols[outc]}{r}")
            checked += 1
            if exp is None:
                if got is not None:
                    bad += 1
            elif got is None or abs(got - exp) > 1e-12:
                bad += 1; print("BAD AVG", cols[outc], r, "got", got, "want", exp)

nb = nu = nf = 0
for r in range(3, 48):
    for c in range(2, 24):
        addr = f"{cols[c]}{r}"
        xf = xfs[cell_styles[addr]]
        font = fonts[int(re.search(r'fontId="(\d+)"', xf).group(1))]
        if "<x:b />" in font:
            nb += 1
        if "<x:u />" in font:
            nu += 1
        pt = re.search(r'<x:patternFill patternType="(\w+)"', styles.split("<x:fills")[1].split("</x:fills>")[0])
distinct_fills = re.findall(r'<x:fill>.*?</x:fill>', styles.split("<x:fills")[1].split("</x:fills>")[0], re.S)
print(f"values checked: {checked}  mismatches: {bad}")
print(f"bold (best): {nb}   underlined (second): {nu}")
print(f"fills defined in workbook: {distinct_fills}")
print("count row:", " | ".join(str(cells.get(f'{cols[c]}48')) for c in range(2, 24, 2)))
