#!/usr/bin/env python3
"""Rebuild the non-Traffic experiment registry from local logs."""
import ast, csv, hashlib, json, re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LOGS, OUT = ROOT / "logs", ROOT / "recovery"
DATASETS = ("ETTh1", "ETTh2", "ETTm1", "ETTm2", "ECL", "Weather", "Solar", "Exchange")
HORIZONS = (96, 192, 336, 720)
METRICS = re.compile(r"mse:([0-9.eE+-]+),\s*mae:([0-9.eE+-]+)")

def namespace(line):
    node = ast.parse(line.strip(), mode="eval").body
    return {item.arg: ast.literal_eval(item.value) for item in node.keywords}

def dataset(args):
    text = " ".join(str(args.get(k, "")).lower() for k in ("data", "data_path", "root_path", "model_id"))
    for name in DATASETS[:4]:
        if name.lower() in text: return name
    for token, name in (("weather", "Weather"), ("solar", "Solar"), ("exchange", "Exchange")):
        if token in text: return name
    return "ECL" if "electricity" in text or args.get("data", "").lower() == "ecl" else None

def parse(path):
    text = path.read_text(encoding="utf-8", errors="replace")
    line = next((x for x in text.splitlines() if x.startswith("Namespace(")), None)
    found = METRICS.findall(text)
    if not line or not found: return None
    args = namespace(line); name, pred = dataset(args), args.get("pred_len")
    if name not in DATASETS or pred not in HORIZONS: return None
    mse, mae = map(float, found[-1]); params = re.search(r"Total trainable parameters:\s*(\d+)", text)
    times = [float(x) for x in re.findall(r"Epoch:\s*\d+\s+cost time:\s*([0-9.eE+-]+)", text)]
    return {"dataset": name, "pred_len": pred, "mse": mse, "mae": mae,
            "model_id": args.get("model_id"), "seed": args.get("fix_seed"),
            "trainable_parameters": int(params.group(1)) if params else None,
            "epochs_recorded": len(times), "train_seconds": sum(times) if times else None,
            "log_path": path.relative_to(ROOT).as_posix(), "args": args}

def write_csv(path, rows):
    fixed = ["dataset", "pred_len", "mse", "mae", "model_id", "seed", "trainable_parameters",
             "epochs_recorded", "train_seconds", "log_path"]
    names = sorted({key for row in rows for key in row["args"]} - set(fixed))
    with path.open("w", newline="", encoding="utf-8-sig") as handle:
        writer = csv.DictWriter(handle, fieldnames=fixed + names); writer.writeheader()
        for row in rows:
            flat = {key: row.get(key) for key in fixed}; flat.update({key: row["args"].get(key) for key in names})
            writer.writerow(flat)

def command(row):
    keys = ("is_training model_id model data root_path data_path features target freq seq_len pred_len enc_in "
            "dec_in c_out d_model d_ff e_layers wv m alpha geomattn_dropout dropout use_norm "
            "use_embedding_armor armor_cycle armor_scale armor_dropout armor_lr_scale l1_weight "
            "learning_rate weight_decay batch_size train_epochs patience lradj pct_start des itr fix_seed").split()
    args = row["args"]
    return "python -u run.py " + " ".join(f"--{k} {args[k]}" for k in keys if k in args) + ' --gpu "$GPU"'

def digest(path): return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    OUT.mkdir(exist_ok=True)
    runs = [run for path in sorted(LOGS.rglob("*.log"))
            if "traffic" not in path.as_posix().lower() and (run := parse(path))]
    runs.sort(key=lambda x: (DATASETS.index(x["dataset"]), x["pred_len"], x["mse"]))
    selected = {}
    for run in runs: selected.setdefault((run["dataset"], run["pred_len"]), run)
    missing = [(d, h) for d in DATASETS for h in HORIZONS if (d, h) not in selected]
    if missing: raise RuntimeError(f"Missing completed logs: {missing}")
    best = [selected[(d, h)] for d in DATASETS for h in HORIZONS]
    write_csv(OUT / "all_completed_runs.csv", runs); write_csv(OUT / "best_results_and_configs.csv", best)
    (OUT / "best_configs.json").write_text(json.dumps(best, indent=2), encoding="utf-8")
    lines = ["#!/usr/bin/env bash", "set -euo pipefail", "GPU=${GPU:-0}", "mkdir -p logs/recovered_best", ""]
    for row in best:
        tag = f'{row["dataset"]}_p{row["pred_len"]}'
        lines += [f'echo "Running {tag} on GPU $GPU"', f'{command(row)} > logs/recovered_best/{tag}.log 2>&1', ""]
    runner = OUT / "run_recovered_best.sh"; runner.write_text("\n".join(lines), encoding="ascii", newline="\n")
    files = [ROOT / "run.py", *sorted((ROOT / "model").glob("*.py")), *sorted((ROOT / "layers").glob("*.py")),
             OUT / "best_results_and_configs.csv", OUT / "best_configs.json", runner]
    if (OUT / "best_results.xlsx").exists(): files.append(OUT / "best_results.xlsx")
    (OUT / "SHA256SUMS").write_text("".join(f"{digest(p)}  {p.relative_to(ROOT).as_posix()}\n" for p in files))
    dataset_files = sorted(path for path in (ROOT / "dataset").rglob("*")
                           if path.is_file() and "traffic" not in path.as_posix().lower())
    with (OUT / "dataset_manifest.csv").open("w", newline="", encoding="utf-8-sig") as handle:
        writer = csv.writer(handle); writer.writerow(("path", "bytes", "sha256"))
        writer.writerows((path.relative_to(ROOT).as_posix(), path.stat().st_size, digest(path)) for path in dataset_files)
    print(f"Recovered {len(runs)} runs and {len(best)} best configurations in {OUT}")

if __name__ == "__main__": main()
