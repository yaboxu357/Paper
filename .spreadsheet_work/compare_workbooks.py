#!/usr/bin/env python3
"""Compare the several results workbooks against each other and against the logs."""
import json, math
from pathlib import Path

W = Path("C:/code/codexplace/paper/.spreadsheet_work")
DATASETS = ["ETTh1", "ETTm1", "ETTh2", "ETTm2", "ECL", "Weather", "Solar", "Exchange", "Traffic"]
HORIZONS = [96, 192, 336, 720]


def load(name):
    txt = (W / name).read_text(encoding="utf-8")
    return json.loads(txt.split("=== SHEET Sheet1 ===")[1].strip())["values"]


def parse_wide(vals, models):
    """models: list of (name, mse_col, mae_col). Returns {(ds, len): {model: (mse, mae)}}."""
    out, ds = {}, None
    for row in vals[2:]:
        if row[0]:
            ds = row[0]
        if ds not in DATASETS:
            continue
        k = row[1]
        if k == "AVG":
            key = (ds, "AVG")
        elif isinstance(k, int):
            key = (ds, k)
        else:
            continue
        out[key] = {m: (row[c], row[a]) for m, c, a in models}
    return out


results = load("dump_results.txt")
formatted = load("dump_formatted.txt")
detailed = load("dump_detailed.txt")

R_MODELS = [("E-Armor", 2, 4), ("EMAformer", 6, 7), ("DeepBooTS", 8, 9), ("SimpleTM", 10, 11),
            ("FilterTS", 12, 13), ("xPatch", 14, 15), ("iTransformer", 16, 17), ("TimeMixer", 18, 19),
            ("PatchTST", 20, 21), ("DLinear", 22, 23), ("FEDformer", 24, 25)]
F_MODELS = [("E-Armor", 2, 3), ("EMAformer", 4, 5), ("DeepBooTS", 6, 7), ("SimpleTM", 8, 9),
            ("FilterTS", 10, 11), ("xPatch", 12, 13), ("iTransformer", 14, 15), ("TimeMixer", 16, 17),
            ("PatchTST", 18, 19), ("DLinear", 20, 21), ("FEDformer", 22, 23)]
D_MODELS = [("E-Armor", 2, 3), ("DeepBooTS", 4, 5), ("SimpleTM", 6, 7), ("FilterTS", 8, 9),
            ("xPatch", 10, 11), ("iTransformer", 12, 13), ("TimeMixer", 14, 15), ("PatchTST", 16, 17),
            ("DLinear", 18, 19), ("FEDformer", 20, 21)]

R = parse_wide(results, R_MODELS)
F = parse_wide(formatted, F_MODELS)
D = parse_wide(detailed, D_MODELS)
EPS = 2.220446049250313e-16
trunc3 = lambda x: math.trunc((x + EPS) * 1000) / 1000
round3 = lambda x: math.floor((x + EPS) * 1000 + 0.5) / 1000

print("=== A. E-Armor full-precision column vs the 3-dp display column in results/experiment_results.xlsx ===")
n_round = n_trunc = n_neither = 0
for row in results[2:]:
    if row[0]:
        ds = row[0]
    if ds not in DATASETS or row[1] not in HORIZONS + ["AVG"]:
        continue
    for full, disp, lab in ((row[2], row[3], "MSE"), (row[4], row[5], "MAE")):
        if full is None:
            continue
        if abs(round3(full) - disp) < 1e-12 and abs(trunc3(full) - disp) < 1e-12:
            continue  # both agree, uninformative
        elif abs(round3(full) - disp) < 1e-12:
            n_round += 1
        elif abs(trunc3(full) - disp) < 1e-12:
            n_trunc += 1
            print(f"  TRUNCATED (not rounded) {ds} {row[1]} {lab}: {full:.8f} -> {disp}  (round3 would be {round3(full)})")
        else:
            n_neither += 1
            print(f"  NEITHER {ds} {row[1]} {lab}: full={full} disp={disp}")
print(f"  informative cells: rounded={n_round}, truncated={n_trunc}, neither={n_neither}")

print("\n=== B. outputs/detailed-results-truncated vs results (expect trunc3 of the same source) ===")
diff = 0
for (ds, h), models in D.items():
    for m, (mse, mae) in models.items():
        s_mse, s_mae = R[(ds, h)][m]
        if s_mse is None:
            continue
        ok = abs(trunc3(s_mse) - mse) < 1e-9 and abs(trunc3(s_mae) - mae) < 1e-9
        if not ok:
            diff += 1
            if diff <= 25:
                print(f"  DIFF {ds} {h} {m}: results=({s_mse},{s_mae}) truncated=({trunc3(s_mse)},{trunc3(s_mae)}) detailed=({mse},{mae})")
print(f"  differing cells: {diff} / {sum(len(v) for v in D.values())}")

print("\n=== C. outputs/experiment-results-formatted vs results (formatted built 14:02, results touched 16:03) ===")
diff = 0
for (ds, h), models in F.items():
    for m, (mse, mae) in models.items():
        s_mse, s_mae = R[(ds, h)][m]
        if s_mse is None or mse is None:
            continue
        if abs(round3(s_mse) - mse) > 1e-12 or abs(round3(s_mae) - mae) > 1e-12:
            diff += 1
            if diff <= 40:
                print(f"  DIFF {ds} {h} {m}: results=({s_mse:.6f},{s_mae:.6f}) round3=({round3(s_mse)},{round3(s_mae)}) formatted=({mse},{mae})")
print(f"  differing cells: {diff} / {sum(len(v) for v in F.values())}")
