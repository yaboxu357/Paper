# E-Armor

E-Armor is a multivariate long-term time-series forecasting model that combines wavelet-domain representation, geometric attention, and learnable channel-phase embedding armor.

## Repository contents

- `model/`, `layers/`: model architecture and core modules.
- `data_provider/`, `experiments/`, `utils/`: data loading, training, evaluation, and utilities.
- `scripts/`: dataset-specific experiment and grid-search scripts.
- `tools/recover_experiments.py`: reconstructs experiment registries from local logs.

## Data and experiment outputs

Datasets, logs, checkpoints, and result files are intentionally not committed. Dataset paths and runtime options are defined in `scripts/`.

## Run

Create the environment from `environment.yml`, then launch an experiment from the project root, for example:

```bash
bash scripts/multivariate_forecasting/E_SimpleTM_grid_expanded_ETTh1.sh
```

Individual configurations can also be run with `python -u run.py`.

The retained evaluation uses input length 96 and horizons 96, 192, 336, and 720. Traffic is temporarily excluded.
