#!/usr/bin/env python3
"""Independently re-derive the bold/underline ranks from the workbook's own values."""
import re
import zipfile
from pathlib import Path

XLSX = Path("C:/code/codexplace/paper/outputs/detailed-results/experiment_results_detailed.xlsx")
z = zipfile.ZipFile(XLSX)
styles = z.read("xl/styles.xml").decode()
fonts = re.findall(r"<x:font[ >].*?</x:font>|<x:font ?/>", styles.split("<x:fonts")[1].split("</x:fonts>")[0], re.S)
xfb = styles.split("<x:cellXfs")[1].split("</x:cellXfs>")[0]


def split_xfs(t):
    out, i = [], 0
    while True:
        j = t.find("<x:xf ", i)
        if j < 0:
            return out
        gt = t.find(">", j)
        if t[gt - 1] == "/":
            out.append(t[j:gt + 1]); i = gt + 1
        else:
            e = t.find("</x:xf>", j); out.append(t[j:e + 7]); i = e + 7


xfs = split_xfs(xfb)
wbx = z.read("xl/workbook.xml").decode("utf-8")
rx = z.read("xl/_rels/workbook.xml.rels").decode("utf-8")
relmap = {}
for m in re.finditer(r"<Relationship\b[^>]*/>", rx):
    a = dict(re.findall(r'([\w:]+)="([^"]*)"', m.group(0)))
    relmap[a["Id"]] = a["Target"]
parts = {}
for m in re.finditer(r"<x:sheet\b[^>]*/>", wbx):
    a = dict(re.findall(r'([\w:]+)="([^"]*)"', m.group(0)))
    t = relmap[a["r:id"]].lstrip("/")
    parts[a["name"]] = t if t.startswith("xl/") else "xl/" + t

cols = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
TOTAL = 0
for name, part in parts.items():
    sh = z.read(part).decode("utf-8")
    vals, sid = {}, {}
    for m in re.finditer(r'<x:c\b([^>]*?)(?:/>|>(.*?)</x:c>)', sh, re.S):
        a = dict(re.findall(r'([\w:]+)="([^"]*)"', m.group(1)))
        addr = a.get("r", "")
        sid[addr] = int(a.get("s", 0))
        if a.get("t") not in (None, "n"):        # strings / shared strings
            continue
        v = re.search(r"<x:v>(.*?)</x:v>", m.group(2) or "")
        if v:
            vals[addr] = float(v.group(1))

    def font(addr):
        xf = xfs[sid[addr]]
        return fonts[int(re.search(r'fontId="(\d+)"', xf).group(1))]

    ncols = len([c for c in range(2, 26) if f"{cols[c]}2" in sid])
    bad = bolds = unders = 0
    for r in range(3, 48):
        for off in (0, 1):
            cells = [(f"{cols[c]}{r}", vals.get(f"{cols[c]}{r}")) for c in range(2 + off, 2 + ncols, 2)]
            cells = [(a, v) for a, v in cells if v is not None]
            if not cells:
                continue
            uniq = sorted({v for _, v in cells})
            best = uniq[0]
            second = uniq[1] if len(uniq) > 1 else None
            for a, v in cells:
                f = font(a)
                isb = "<x:b />" in f
                isu = "<x:u />" in f
                bolds += isb
                unders += isu
                if v == best:
                    if not isb:
                        bad += 1; print("NOT BOLD", name, a, v)
                    if isu:
                        bad += 1; print("BOLD AND UNDERLINED", name, a, v)
                elif second is not None and v == second:
                    if not isu:
                        bad += 1; print("NOT UNDERLINED", name, a, v)
                elif isb or isu:
                    bad += 1; print("WRONGLY MARKED", name, a, v, "best", best, "second", second)
    print(f"{name}: rank mismatches {bad} | bold cells {bolds} | underlined cells {unders}")
    TOTAL += bad
print("TOTAL RANK MISMATCHES:", TOTAL)
