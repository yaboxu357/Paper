# E-Armor

E-Armor is a multivariate long-term time-series forecasting model that combines wavelet-domain representation, geometric attention, and learnable channel-phase embedding armor.

## Repository contents

- `model/`, `layers/`: model architecture and core modules.
- `data_provider/`, `experiments/`, `utils/`: data loading, training, evaluation, and utilities.
- `scripts/`: dataset-specific experiment and grid-search scripts.
- `recovery/`: recovered metrics, full configurations, integrity manifests, and rerun scripts.
- `results/experiment_results.xlsx`: consolidated experimental results.
- `figures/`: project figures retained with the source package.
- [Release `recovery-v1`](https://github.com/yaboxu357/Paper/releases/tag/recovery-v1): complete dataset and experiment-log archives.
- `artifacts/SHA256SUMS`: archive integrity checksums.

Traffic data and logs are included in the archives, but Traffic remains excluded from the current recovered result table and evaluation plan.

## Restore data and logs

From the repository root:

```bash
curl -L -o artifacts/datasets.tar.gz https://github.com/yaboxu357/Paper/releases/download/recovery-v1/datasets.tar.gz
curl -L -o artifacts/logs.tar.gz https://github.com/yaboxu357/Paper/releases/download/recovery-v1/logs.tar.gz
tar -xzf artifacts/datasets.tar.gz
tar -xzf artifacts/logs.tar.gz
sha256sum -c artifacts/SHA256SUMS
```

The reconstructed archive and log archive restore the original `dataset/` and `logs/` directory structures expected by the scripts.

## Environment and run

Create the environment from `environment.yml`. An individual experiment can then be started with a script such as:

```bash
bash scripts/multivariate_forecasting/E_SimpleTM_grid_expanded_ETTh1.sh
```

Recovered best configurations are stored in `recovery/best_results_and_configs.csv` and `recovery/best_configs.json`. To rerun all retained configurations on one selected GPU:

```bash
GPU=0 bash recovery/run_recovered_best.sh
```

## Recovered evaluation scope

The canonical recovery table contains eight datasets and prediction horizons of 96, 192, 336, and 720. The retained experiments use the configured single seed 2025. Best runs are selected by final test MSE, with MAE taken from the same run.
