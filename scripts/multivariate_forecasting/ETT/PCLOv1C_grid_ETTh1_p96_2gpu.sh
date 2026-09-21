#!/usr/bin/env bash
set -u

script_dir=$(cd "$(dirname "$0")" && pwd)
project_root=$(cd "$script_dir/../../.." && pwd)
cd "$project_root"

log_dir=logs/pclov1c_grid_etth1_p96
mkdir -p "$log_dir"
lock_dir="$log_dir/.run_lock"
if ! mkdir "$lock_dir" 2>/dev/null; then
  echo "PCLO-v1-C grid is already running; refusing to overwrite its logs." >&2
  exit 1
fi
trap 'rmdir "$lock_dir"' EXIT

ranks=(4 8 16)
gate_inits=(0.01 0.03 0.05)
operator_lr_scales=(0.25 0.5 1.0)

run_worker() {
  physical_gpu=$1
  slot=$2
  index=0

  for rank in "${ranks[@]}"; do
    for gate_init in "${gate_inits[@]}"; do
      for operator_lr_scale in "${operator_lr_scales[@]}"; do
        if [ $((index % 2)) -eq "$slot" ]; then
          tag="r${rank}_g${gate_init}_olr${operator_lr_scale}"
          log_file="$log_dir/${tag}.log"
          status_file="$log_dir/${tag}.status"
          echo "GPU ${physical_gpu}: ${tag}"
          if CUDA_VISIBLE_DEVICES="$physical_gpu" python -u run.py \
            --is_training 1 \
            --root_path ./dataset/ETT-small/ \
            --data_path ETTh1.csv \
            --model_id "ETTh1_p96_PCLOv1C_${tag}" \
            --model SimpleTM \
            --data ETTh1 \
            --features M \
            --seq_len 96 \
            --pred_len 96 \
            --enc_in 7 \
            --dec_in 7 \
            --c_out 7 \
            --d_model 64 \
            --d_ff 64 \
            --e_layers 1 \
            --learning_rate 0.02 \
            --alpha 0.3 \
            --m 3 \
            --l1_weight 0.0005 \
            --armor_scale 1.25 \
            --armor_dropout 0.0 \
            --armor_lr_scale 1.4 \
            --use_embedding_armor 1 \
            --use_pclo 1 \
            --pclo_calibrate 1 \
            --operator_rank "$rank" \
            --operator_hidden 32 \
            --operator_gate_init "$gate_init" \
            --operator_dropout 0.0 \
            --operator_lr_scale "$operator_lr_scale" \
            --gate_lr_scale 1.0 \
            --batch_size 256 \
            --train_epochs 10 \
            --patience 3 \
            --lradj TST \
            --pct_start 0.2 \
            --weight_decay 0.01 \
            --fix_seed 2025 \
            --des PCLOv1C \
            --gpu 0 > "$log_file" 2>&1; then
            echo 0 > "$status_file"
          else
            echo $? > "$status_file"
          fi
        fi
        index=$((index + 1))
      done
    done
  done
}

run_worker 0 0 &
worker0=$!
run_worker 1 1 &
worker1=$!
wait "$worker0"
wait "$worker1"

summary_file="$log_dir/summary.csv"
echo "rank,gate_init,operator_lr_scale,mse,mae,status" > "$summary_file"
for rank in "${ranks[@]}"; do
  for gate_init in "${gate_inits[@]}"; do
    for operator_lr_scale in "${operator_lr_scales[@]}"; do
      tag="r${rank}_g${gate_init}_olr${operator_lr_scale}"
      log_file="$log_dir/${tag}.log"
      status_file="$log_dir/${tag}.status"
      status=1
      if [ -f "$status_file" ]; then
        status=$(cat "$status_file")
      fi
      metric_line=$(grep '^mse:' "$log_file" 2>/dev/null | tail -n 1 || true)
      if [ -n "$metric_line" ]; then
        mse=$(echo "$metric_line" | sed -E 's/.*mse:([^,]+), mae:.*/\1/')
        mae=$(echo "$metric_line" | sed -E 's/.*mae:([^ ]+).*/\1/')
        echo "$rank,$gate_init,$operator_lr_scale,$mse,$mae,$status" >> "$summary_file"
      else
        echo "$rank,$gate_init,$operator_lr_scale,,,$status" >> "$summary_file"
      fi
    done
  done
done

{
  head -n 1 "$summary_file"
  tail -n +2 "$summary_file" | sort -t, -k4,4g
} > "$log_dir/summary_sorted.csv"

cat "$log_dir/summary_sorted.csv"
