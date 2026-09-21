# Experiment Recovery

This is the canonical recovery bundle for the current E-Armor model.

## Scope

- Datasets: ETTh1, ETTh2, ETTm1, ETTm2, ECL, Weather, Solar, Exchange.
- Horizons: 96, 192, 336, 720.
- Traffic is intentionally excluded until its dataset is restored.
- All retained experiments use the configured single seed; multi-seed validation is out of scope.
- The best run is selected by minimum final test MSE, with MAE from the same run.

## Files

- `best_results_and_configs.csv`: canonical 32-row metric and full-configuration table.
- `best_results.xlsx`: presentation workbook with all recovered best metrics and parameters.
- `best_configs.json`: lossless machine-readable selected log records.
- `all_completed_runs.csv`: every completed non-Traffic run recovered from logs.
- `run_recovered_best.sh`: reruns the 32 configurations; set `GPU` before launch.
- `SHA256SUMS`: integrity hashes for model code and recovery outputs.
- `dataset_manifest.csv`: sizes and SHA-256 hashes for the eight restored datasets.

Rebuild from the project root with `python tools/recover_experiments.py`.
The original logs remain the source evidence; the existing Excel workbook is a presentation copy.
