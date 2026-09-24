#!/usr/bin/env python3
"""Dump the reference recommendations workbook (values + styling) as UTF-8 text."""
import re
import zipfile
from pathlib import Path

SRC = Path("C:/code/codexplace/paper/outputs/baseline-selection-1-3-5/baseline_selection_recommendations.xlsx")
OUT = Path("C:/code/codexplace/paper/.spreadsheet_work/ref_dump.txt")

z = zipfile.ZipFile(SRC)
shared = [re.sub(r"<[^>]+>", "", s) for s in re.findall(r"<x:si>(.*?)</x:si>", z.read("xl/sharedStrings.xml").decode(), re.S)]
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


def style_desc(sid):
    if sid is None:
        return "default"
    xf = xfs[int(sid)]
    fid = int(re.search(r'fontId="(\d+)"', xf).group(1))
    flid = int(re.search(r'fillId="(\d+)"', xf).group(1))
    nf = re.search(r'numFmtId="(\d+)"', xf)
    f = fonts[fid]
    bits = []
    if "<x:b />" in f:
        bits.append("bold")
    if "<x:u />" in f:
        bits.append("underline")
    nm = re.search(r'<x:name val="([^"]+)"', f)
    sz = re.search(r'<x:sz val="([^"]+)"', f)
    cl = re.search(r'<x:color rgb="([^"]+)"', f)
    bits.append(f"{nm.group(1) if nm else '?'}/{sz.group(1) if sz else '?'}/{cl.group(1) if cl else '?'}")
    fill = fills[flid]
    fc = re.search(r'<x:fgColor rgb="([^"]+)"', fill)
    if fc:
        bits.append(f"fill={fc.group(1)}")
    if nf and nf.group(1) != "0":
        bits.append(f"fmt={nf.group(1)}")
    return ",".join(bits)


wb = z.read("xl/workbook.xml").decode()
rels = z.read("xl/_rels/workbook.xml.rels").decode()
relmap = {}
for m in re.finditer(r"<Relationship\b[^>]*/>", rels):
    attrs = dict(re.findall(r'(\w+)="([^"]*)"', m.group(0)))
    relmap[attrs["Id"]] = attrs["Target"]

sheets = re.findall(r'<x:sheet[^>]*/>', wb)
lines = []
for s in sheets:
    attrs = dict(re.findall(r'(\w+)="([^"]*)"', s))
    name, rid = attrs.get("name"), attrs.get("r:id") or attrs.get("id")
    target = relmap[rid].lstrip("/")
    if not target.startswith("xl/"):
        target = "xl/" + target
    sh = z.read(target).decode()
    lines.append("=" * 100)
    lines.append(f"SHEET: {name}   ({target})")
    lines.append("=" * 100)
    merges = re.findall(r'<x:mergeCell ref="([^"]+)"', sh)
    if merges:
        lines.append("MERGES: " + ", ".join(merges))
    for m in re.finditer(r'<x:row r="(\d+)"[^>]*>(.*?)</x:row>|<x:row r="(\d+)"[^>]*/>', sh, re.S):
        r = int(m.group(1) or m.group(3))
        inner = m.group(2) or ""
        out = []
        for c in re.finditer(r'<x:c r="([A-Z]+)(\d+)"(?: s="(\d+)")?(?: t="(\w+)")?\s*(?:/>|>(.*?)</x:c>)', inner, re.S):
            col, sid, typ, cv = c.group(1), c.group(3), c.group(4), c.group(5)
            v = re.search(r"<x:v>(.*?)</x:v>", cv or "")
            isv = re.search(r"<x:is>(.*?)</x:is>", cv or "", re.S)
            if isv:
                val = re.sub(r"<[^>]+>", "", isv.group(1))
            elif not v:
                continue
            else:
                val = shared[int(v.group(1))] if typ == "s" else v.group(1)
            out.append(f"{col}={val} [{style_desc(sid)}]")
        if out:
            lines.append(f"[r{r:>3}] " + " | ".join(out))
    lines.append("")
OUT.write_text("\n".join(lines), encoding="utf-8")
print("wrote", OUT, "lines:", len(lines))
