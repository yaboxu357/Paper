#!/usr/bin/env bash
set -u

script_dir=$(cd "$(dirname "$0")" && pwd)
project_root=$(cd "$script_dir/../.." && pwd)
log_dir="$project_root/logs"
mkdir -p "$log_dir"

GPU_ID=0 bash "$script_dir/E_Armor_grid_v2.sh" ETTh1 \
  > "$log_dir/earmor_grid_v2_ETTh1_master.log" 2>&1 &
etth1_pid=$!

GPU_ID=0 bash "$script_dir/E_Armor_grid_v2.sh" ETTm1 \
  > "$log_dir/earmor_grid_v2_ETTm1_master.log" 2>&1 &
ettm1_pid=$!

GPU_ID=1 bash "$script_dir/E_Armor_grid_v2.sh" ECL \
  > "$log_dir/earmor_grid_v2_ECL_master.log" 2>&1 &
ecl_pid=$!

echo "GPU 0: ETTh1 PID ${etth1_pid}, ETTm1 PID ${ettm1_pid}"
echo "GPU 1: ECL PID ${ecl_pid}"
wait "$etth1_pid" "$ettm1_pid" "$ecl_pid"
echo "All E-Armor grids are complete."
