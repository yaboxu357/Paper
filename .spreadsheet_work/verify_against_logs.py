#!/usr/bin/env python3
"""Independently re-derive results from logs and compare with the results workbook."""
import ast, csv, json, re, sys
from pathlib import Path

ROOT = Path("C:/code/codexplace/paper")
LOGS = ROOT / "logs"
METRICS = re.compile(r"mse:([0-9.eE+-]+),\s*mae:([0-9.eE+-]+)")
DATASETS = ("ETTh1", "ETTh2", "ETTm1", "ETTm2", "ECL", "Weather", "Solar", "Exchange", "Traffic")
HORIZONS = (96, 192, 336, 720)


def namespace(line):
    node = ast.parse(line.strip(), mode="eval").body
    return {i.arg: ast.literal_eval(i.value) for i in node.keywords}


def dataset(args):
    text = " ".join(str(args.get(k, "")).lower() for k in ("data", "data_path", "root_path", "model_id"))
    for name in DATASETS[:4]:
        if name.lower() in text:
            return name
    for token, name in (("weather", "Weather"), ("solar", "Solar"), ("exchange", "Exchange"), ("traffic", "Traffic")):
        if token in text:
            return name
    return "ECL" if "electricity" in text or args.get("data", "").lower() == "ecl" else None


def parse(path):
    text = path.read_text(encoding="utf-8", errors="replace")
    line = next((x for x in text.splitlines() if x.startswith("Namespace(")), None)
    found = METRICS.findall(text)
    if not line or not found:
        return None
    args = namespace(line)
    name, pred = dataset(args), args.get("pred_len")
    if name not in DATASETS or pred not in HORIZONS:
        return None
    mse, mae = map(float, found[-1])
    return {"dataset": name, "pred_len": pred, "mse": mse, "mae": mae,
            "model_id": args.get("model_id"), "args": args,
            "log_path": path.relative_to(ROOT).as_posix(),
            "n_metric_lines": len(found)}


def select_balanced(group):
    mse_min, mse_max = min(r["mse"] for r in group), max(r["mse"] for r in group)
    mae_min, mae_max = min(r["mae"] for r in group), max(r["mae"] for r in group)

    def rank(r):
        m = (r["mse"] - mse_min) / (mse_max - mse_min) if mse_max > mse_min else 0.0
        a = (r["mae"] - mae_min) / (mae_max - mae_min) if mae_max > mae_min else 0.0
        preferred = 0 if "/esimpletm_grid_expanded_" in r["log_path"] else 1
        return ((m + a) / 2.0, r["mse"], r["mae"], preferred, r["model_id"] or "", r["log_path"])

    return min(group, key=rank)


runs = [r for p in sorted(LOGS.rglob("*.log")) if (r := parse(p))]
print(f"parsed runs: {len(runs)}")

# ---- build workbook view from dump ----
dump = (ROOT / ".spreadsheet_work" / "dump_results.txt").read_text(encoding="utf-8")
vals = json.loads(dump.split("=== SHEET Sheet1 ===")[1].strip())["values"]
sheet = {}
avg_rows = {}
order = []
for row in vals[2:]:
    if row[0]:
        ds = row[0]
        order.append(ds)
    if row[1] == "AVG":
        avg_rows[ds] = {"mse": row[2], "mae": row[4], "mse_r": row[3], "mae_r": row[5]}
    elif isinstance(row[1], int):
        sheet[(ds, row[1])] = {"mse": row[2], "mae": row[4], "mse_r": row[3], "mae_r": row[5],
                               "baselines": row[6:26]}
print("workbook datasets:", order)

# ---- 1. compare workbook E-Armor columns with logs ----
print("\n=== 1. workbook E-Armor metrics vs re-derived best from logs ===")
mismatch = 0
for ds in order:
    for h in HORIZONS:
        group = [r for r in runs if r["dataset"] == ds and r["pred_len"] == h]
        if not group:
            print(f"  !! {ds} {h}: NO LOGS")
            continue
        best = select_balanced(group)
        wb = sheet[(ds, h)]
        ok_mse = abs(best["mse"] - wb["mse"]) < 1e-12
        ok_mae = abs(best["mae"] - wb["mae"]) < 1e-12
        round_ok = (round(wb["mse"], 3) == wb["mse_r"]) and (round(wb["mae"], 3) == wb["mae_r"])
        if not (ok_mse and ok_mae):
            mismatch += 1
            print(f"  MISMATCH {ds} {h}: wb=({wb['mse']},{wb['mae']}) logs=({best['mse']},{best['mae']}) "
                  f"from {best['log_path']}  n_runs={len(group)}")
        if not round_ok:
            print(f"  ROUNDING {ds} {h}: mse {wb['mse']}->{wb['mse_r']} mae {wb['mae']}->{wb['mae_r']}")
print(f"metric mismatches: {mismatch} / 36")

# ---- 2. AVG rows ----
print("\n=== 2. AVG rows ===")
for ds in order:
    got_mse = sum(sheet[(ds, h)]["mse"] for h in HORIZONS) / 4
    got_mae = sum(sheet[(ds, h)]["mae"] for h in HORIZONS) / 4
    a = avg_rows[ds]
    print(f"  {ds}: avg mse sheet={a['mse']:.10f} recomputed={got_mse:.10f} {'OK' if abs(a['mse']-got_mse)<1e-12 else 'MISMATCH'}"
          f" | mae sheet={a['mae']:.10f} recomputed={got_mae:.10f} {'OK' if abs(a['mae']-got_mae)<1e-12 else 'MISMATCH'}")

# ---- 3. best_configs.json vs log Namespace ----
print("\n=== 3. best_configs.json args vs the referenced log's Namespace line ===")
cfgs = json.loads((ROOT / "recovery" / "best_configs.json").read_text(encoding="utf-8"))
bad = 0
for c in cfgs:
    p = ROOT / c["log_path"]
    if not p.exists():
        print(f"  MISSING LOG {c['log_path']}")
        bad += 1
        continue
    text = p.read_text(encoding="utf-8", errors="replace")
    line = next(x for x in text.splitlines() if x.startswith("Namespace("))
    actual = namespace(line)
    diffs = {k: (v, actual.get(k)) for k, v in c["args"].items() if actual.get(k) != v}
    extra = {k: v for k, v in actual.items() if k not in c["args"]}
    if diffs or extra:
        bad += 1
        print(f"  DIFF {c['dataset']} {c['pred_len']} {c['model_id']}: {diffs} extra={extra}")
    if c["model_id"] != actual.get("model_id"):
        print(f"  ID MISMATCH {c['log_path']}")
print(f"config entries with differences: {bad} / {len(cfgs)}")

# ---- 4. workbook metrics vs recovery csv ----
print("\n=== 4. workbook E-Armor metrics vs recovery/best_results_and_configs.csv ===")
csv_rows = list(csv.DictReader((ROOT / "recovery" / "best_results_and_configs.csv").open(encoding="utf-8-sig")))
d = 0
for r in csv_rows:
    ds, h = r["dataset"], int(r["pred_len"])
    wb = sheet[(ds, h)]
    if abs(float(r["mse"]) - wb["mse"]) > 1e-12 or abs(float(r["mae"]) - wb["mae"]) > 1e-12:
        d += 1
        print(f"  DIFF {ds} {h}: csv=({r['mse']},{r['mae']}) wb=({wb['mse']},{wb['mae']})")
print(f"csv entries differing from workbook: {d} / {len(csv_rows)}")

# ---- 5. dataset / horizon coverage & config spread ----
print("\n=== 5. selected configs per dataset (dataset-specific parameters) ===")
keys = ["data", "root_path", "data_path", "data", "wv", "m", "alpha", "alpha", "d_model", "d_ff", "e_layers",
        "armor_cycle", "armor_scale", "armor_dropout", "armor_lr_scale", "l1_weight", "learning_rate",
        "weight_decay", "dropout", "geomattn_dropout", "batch_size", "seq_len", "train_epochs", "patience",
        "use_norm", "use_embedding_armor", "lradj", "pct_start", "fix_seed", "num_workers", "des"]
keys = list(dict.fromkeys(keys))
for ds in order:
    rows = [c for c in cfgs if c["dataset"] == ds]
    print(f"\n  --- {ds} ---")
    for k in keys:
        col = [r["args"].get(k) for r in sorted(rows, key=lambda x: x["pred_len"])]
        print(f"    {k:20s} {col}")
