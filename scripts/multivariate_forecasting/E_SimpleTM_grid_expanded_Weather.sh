#!/usr/bin/env bash
set -u
GPU_ID=${GPU_ID:-0}
export GPU_ID
script_dir=$(cd "$(dirname "$0")" && pwd)
exec bash "$script_dir/E_SimpleTM_grid_ETT2.sh" Weather
