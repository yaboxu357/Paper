#!/usr/bin/env bash
set -u
export GPU_ID=${GPU_ID:-1}
script_dir=$(cd "$(dirname "$0")" && pwd)
bash "$script_dir/../E_SimpleTM_night_grid.sh" ETTm1
