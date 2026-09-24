#!/usr/bin/env python3
"""Standards-level check of the generated detailed workbook, straight from the OOXML parts.

Checks values (truncation of the source), the bold/underline ranks, and that no
fill colour was applied.
"""
import json
import math
import re
import zipfile
from pathlib import Path

ROOT = Path("C:/code/codexplace/paper")
W = ROOT / ".spreadsheet_work"
XLSX = ROOT / "outputs/detailed-results/experiment_results_detailed.xlsx"

src = json.loads((W / "dump_results.txt").read_text(encoding="utf-8").split("=== SHEET Sheet1 ===")[1].strip())["values"]
roster_avg = json.loads((W / "roster_avg.json").read_text(encoding="utf-8"))

LOCAL = {"E-Armor": (2, 4), "EMAformer": (6, 7), "DeepBooTS": (8, 9), "SimpleTM": (10, 11), "FilterTS": (12, 13),
         "xPatch": (14, 15), "iTransformer": (16, 17), "TimeMixer": (18, 19), "PatchTST": (20, 21),
         "DLinear": (22, 23), "FEDformer": (24, 25)}
MAIN = ["E-Armor", "DeepBooTS", "SimpleTM", "FilterTS", "FACTS", "iTransformer", "TimeMixer", "PatchTST", "TimesNet", "FEDformer"]
APPENDIX = ["EMAformer", "xPatch", "DLinear"]
PAPER_ONLY = {"FACTS", "TimesNet"}
DATASETS = ["ETTh1", "ETTm1", "ETTh2", "ETTm2", "ECL", "Weather", "Solar", "Exchange", "Traffic"]
HORIZONS = [96, 192, 336, 720]

z = zipfile.ZipFile(XLSX)
styles = z.read("xl/styles.xml").decode()
fonts = re.findall(r"<x:font[ >].*?</x:font>|<x:font ?/>", styles.split("<x:fonts")[1].split("</x:fonts>")[0], re.S)
fills = re.findall(r"<x:fill>.*?</x:fill>", styles.split("<x:fills")[1].split("</x:fills>")[0], re.S)
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
workbook_xml = z.read("xl/workbook.xml").decode("utf-8")
rels_xml = z.read("xl/_rels/workbook.xml.rels").decode("utf-8")
relmap = {}
for m in re.finditer(r"<Relationship\b[^>]*/>", rels_xml):
    a = dict(re.findall(r'([\w:]+)="([^"]*)"', m.group(0)))
    relmap[a["Id"]] = a["Target"]
sheet_parts = {}
for m in re.finditer(r"<x:sheet\b[^>]*/>", workbook_xml):
    a = dict(re.findall(r'([\w:]+)="([^"]*)"', m.group(0)))
    t = relmap[a["r:id"]].lstrip("/")
    sheet_parts[a["name"]] = t if t.startswith("xl/") else "xl/" + t

trunc3 = lambda x: math.trunc((float(x) + 2.220446049250313e-16) * 1000) / 1000


def read_sheet(part):
    sh = z.read(part).decode("utf-8")
    cells, cell_styles = {}, {}
    for m in re.finditer(r'<x:c\b([^>]*?)(?:/>|>(.*?)</x:c>)', sh, re.S):
        a = dict(re.findall(r'([\w:]+)="([^"]*)"', m.group(1)))
        inner = m.group(2) or ""
        addr = a.get("r", "")
        cell_styles[addr] = int(a.get("s", 0))
        v = re.search(r"<x:v>(.*?)</x:v>", inner)
        if v:
            cells[addr] = v.group(1)
    return cells, cell_styles


failures = 0
for sheet_name, models in [("主表", MAIN), ("附录", APPENDIX)]:
    cells, cell_styles = read_sheet(sheet_parts[sheet_name])
    cols = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    bad = checked = blanks = 0
    for d in range(9):
        s0 = 2 + d * 5
        for h in range(4):
            r = 3 + d * 5 + h
            for mi, model in enumerate(models):
                for k, outc in enumerate((2 + mi * 2, 3 + mi * 2)):
                    addr = f"{cols[outc]}{r}"
                    if model in PAPER_ONLY:                       # no local per-horizon result
                        if addr in cells:
                            bad += 1; print("UNEXPECTED", sheet_name, addr, cells[addr])
                        else:
                            blanks += 1
                        continue
                    col = LOCAL[model][k]
                    sv = src[s0 + h][col]
                    exp = None if sv is None else trunc3(sv)
                    got = cells.get(addr)
                    checked += 1
                    if exp is None:
                        if got is not None:
                            bad += 1; print("WANT BLANK", sheet_name, addr, got)
                    elif got is None or abs(float(got) - exp) > 1e-12:
                        bad += 1; print("BAD", sheet_name, addr, "got", got, "want", exp)
        r = 3 + d * 5 + 4
        for mi, model in enumerate(models):
            for k, outc in enumerate((2 + mi * 2, 3 + mi * 2)):
                addr = f"{cols[outc]}{r}"
                if model in PAPER_ONLY:
                    pair = roster_avg[DATASETS[d]][model]
                    exp, got = pair[k], cells.get(addr)
                else:
                    col = LOCAL[model][k]
                    vals = [src[s0 + h][col] for h in range(4) if src[s0 + h][col] is not None]
                    exp = trunc3(sum(vals) / 4) if len(vals) == 4 else None
                    got = cells.get(addr)
                checked += 1
                if exp is None:
                    if got is not None:
                        bad += 1
                elif got is None or abs(float(got) - exp) > 1e-12:
                    bad += 1; print("BAD AVG", sheet_name, addr, "got", got, "want", exp)

    nb = nu = nf = 0
    for r in range(3, 48):
        for c in range(2, 2 + len(models) * 2):
            addr = f"{cols[c]}{r}"
            xf = xfs[cell_styles[addr]]
            font = fonts[int(re.search(r'fontId="(\d+)"', xf).group(1))]
            fill = fills[int(re.search(r'fillId="(\d+)"', xf).group(1))]
            if "<x:b />" in font:
                nb += 1
            if "<x:u />" in font:
                nu += 1
            if 'patternType="solid"' in fill:
                nf += 1
    counts = [cells.get(f"{cols[2 + i * 2]}48") for i in range(len(models))]
    print(f"{sheet_name}: values {checked} ({blanks} paper-only blanks)  mismatches {bad}")
    print(f"{sheet_name}: bold {nb}  underlined {nu}  solid-filled {nf}")
    print(f"{sheet_name}: 1 count = " + " | ".join(f"{m}:{c}" for m, c in zip(models, counts)))
    failures += bad

print("KNOWN FILLS:", fills)
print("TOTAL MISMATCHES:", failures)
