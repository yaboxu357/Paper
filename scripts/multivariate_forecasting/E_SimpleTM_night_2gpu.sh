#!/usr/bin/env bash
set -u

script_dir=$(cd "$(dirname "$0")" && pwd)
log_dir="$script_dir/../../logs"
mkdir -p "$log_dir"

(
  echo "GPU 0: starting ETTh1"
  GPU_ID=0 bash "$script_dir/ETT/E_SimpleTM_night_ETTh1.sh"
  echo "GPU 0: ETTh1 complete; starting Weather"
  GPU_ID=0 bash "$script_dir/Weather/E_SimpleTM_night_Weather.sh"
) > "$log_dir/night_gpu0_ETTh1_then_Weather.log" 2>&1 &
gpu0_pid=$!

(
  echo "GPU 1: starting ETTm1"
  GPU_ID=1 bash "$script_dir/ETT/E_SimpleTM_night_ETTm1.sh"
) > "$log_dir/night_gpu1_ETTm1.log" 2>&1 &
gpu1_pid=$!

echo "Started GPU 0 queue (PID $gpu0_pid) and GPU 1 queue (PID $gpu1_pid)"
wait "$gpu0_pid" "$gpu1_pid"
echo "All three night grids are complete"
