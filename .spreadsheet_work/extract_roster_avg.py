#!/usr/bin/env python3
"""Pull the FACTS / TimesNet dataset averages out of the baseline-selection workbook.

These two models are in the recommended roster but have no local runs, so the
only numbers that exist for them are the paper-sourced dataset averages listed
on the 「九数据集均值」 sheet.
"""
import json
import re
import zipfile
from pathlib import Path

ROOT = Path("C:/code/codexplace/paper")
SRC = ROOT / "outputs/baseline-selection-1-3-5/baseline_selection_recommendations.xlsx"
OUT = ROOT / ".spreadsheet_work/roster_avg.json"

DATASETS = ["ETTh1", "ETTm1", "ETTh2", "ETTm2", "ECL", "Weather", "Solar", "Exchange", "Traffic"]
# FACTS = columns J/K, TimesNet = columns R/S on the dataset-average sheet
COLUMNS = {"FACTS": ("J", "K"), "TimesNet": ("R", "S")}

z = zipfile.ZipFile(SRC)
shared = [re.sub(r"<[^>]+>", "", s) for s in re.findall(r"<x:si>(.*?)</x:si>", z.read("xl/sharedStrings.xml").decode(), re.S)]
sheet = z.read("xl/worksheets/sheet3.xml").decode()

cells = {}
for m in re.finditer(r"<x:c\b([^>]*?)(?:/>|>(.*?)</x:c>)", sheet, re.S):
    attrs = dict(re.findall(r'(\w+)="([^"]*)"', m.group(1)))
    inner = m.group(2) or ""
    addr = re.match(r"([A-Z]+)(\d+)$", attrs.get("r", ""))
    if not addr:
        continue
    col, row = addr.group(1), int(addr.group(2))
    if row < 5 or row > 13:
        continue
    v = re.search(r"<x:v>(.*?)</x:v>", inner)
    if not v:
        continue
    t = attrs.get("t")
    if t == "s":                      # shared string index
        cells[(col, row)] = shared[int(v.group(1))]
    elif t in ("str", "inlineStr"):   # literal string held in <v>
        cells[(col, row)] = v.group(1)
    else:
        cells[(col, row)] = float(v.group(1))

out = {}
for i, ds in enumerate(DATASETS):
    row = 5 + i
    if cells.get(("A", row)) != ds:
        raise SystemExit(f"row {row} holds {cells.get(('A', row))!r}, expected {ds!r}")
    entry = {}
    for model, (mc, ac) in COLUMNS.items():
        mse, mae = cells.get((mc, row)), cells.get((ac, row))
        if mse is not None and mae is not None:
            entry[model] = [mse, mae]
    out[ds] = entry

OUT.write_text(json.dumps(out, ensure_ascii=False, indent=1), encoding="utf-8")
print(f"wrote {OUT}")
for ds in DATASETS:
    print(f"  {ds:9s} " + "  ".join(f"{m}={out[ds].get(m)}" for m in COLUMNS))
