#!/usr/bin/env bash
set -u

script_dir=$(cd "$(dirname "$0")" && pwd)
project_root=$(cd "$script_dir/../../.." && pwd)
cd "$project_root"

log_dir=logs/srmd_etth1_stage1
mkdir -p "$log_dir"
lock_dir="$log_dir/.run_lock"
if ! mkdir "$lock_dir" 2>/dev/null; then
  echo "SRMD stage 1 is already running; refusing to overwrite logs." >&2
  exit 1
fi
trap 'rmdir "$lock_dir" 2>/dev/null || true' EXIT

max_jobs=${MAX_JOBS:-4}
case "$max_jobs" in
  ''|*[!0-9]*)
    echo "MAX_JOBS must be an integer from 1 to 10." >&2
    exit 1
    ;;
esac
if [ "$max_jobs" -lt 1 ] || [ "$max_jobs" -gt 10 ]; then
  echo "MAX_JOBS must be between 1 and 10." >&2
  exit 1
fi

horizons=(96 192 336 720)
variants=(baseline srmd)

run_case() {
  pred_len=$1
  variant=$2

  case "$pred_len" in
    96)
      d_model=64; d_ff=64; e_layers=1; learning_rate=0.02
      alpha=0.3; m=3; l1_weight=0.0005
      armor_scale=1.25; armor_dropout=0.0
      ;;
    192)
      d_model=32; d_ff=32; e_layers=1; learning_rate=0.02
      alpha=1.0; m=2; l1_weight=0.00005
      armor_scale=0.75; armor_dropout=0.0
      ;;
    336)
      d_model=64; d_ff=128; e_layers=3; learning_rate=0.002
      alpha=0.0; m=3; l1_weight=0.0
      armor_scale=1.25; armor_dropout=0.1
      ;;
    720)
      d_model=64; d_ff=256; e_layers=2; learning_rate=0.009
      alpha=0.9; m=1; l1_weight=0.0005
      armor_scale=1.25; armor_dropout=0.0
      ;;
    *)
      echo "Unsupported prediction length: $pred_len" >&2
      return 2
      ;;
  esac

  use_srmd=0
  if [ "$variant" = srmd ]; then
    use_srmd=1
  fi
  tag="p${pred_len}_${variant}"
  log_file="$log_dir/${tag}.log"
  status_file="$log_dir/${tag}.status"
  echo "GPU 0: starting ${tag}"

  if CUDA_VISIBLE_DEVICES=0 python -u run.py \
    --is_training 1 \
    --root_path ./dataset/ETT-small/ \
    --data_path ETTh1.csv \
    --model_id "ETTh1_SRMD_${tag}" \
    --model SimpleTM \
    --data ETTh1 \
    --features M \
    --seq_len 96 \
    --pred_len "$pred_len" \
    --enc_in 7 \
    --dec_in 7 \
    --c_out 7 \
    --d_model "$d_model" \
    --d_ff "$d_ff" \
    --e_layers "$e_layers" \
    --learning_rate "$learning_rate" \
    --alpha "$alpha" \
    --m "$m" \
    --l1_weight "$l1_weight" \
    --armor_scale "$armor_scale" \
    --armor_dropout "$armor_dropout" \
    --armor_lr_scale 1.4 \
    --use_embedding_armor 1 \
    --use_srmd "$use_srmd" \
    --segment_len 24 \
    --segment_hidden "$d_model" \
    --segment_dropout 0.0 \
    --coarse_loss_weight 0.2 \
    --batch_size 256 \
    --num_workers 2 \
    --train_epochs 10 \
    --patience 3 \
    --lradj TST \
    --pct_start 0.2 \
    --weight_decay 0.01 \
    --fix_seed 2025 \
    --des SRMD_Stage1 \
    --gpu 0 > "$log_file" 2>&1; then
    echo 0 > "$status_file"
  else
    exit_code=$?
    echo "$exit_code" > "$status_file"
  fi
  echo "GPU 0: finished ${tag} (status $(cat "$status_file"))"
}

for pred_len in "${horizons[@]}"; do
  for variant in "${variants[@]}"; do
    while [ "$(jobs -pr | wc -l)" -ge "$max_jobs" ]; do
      wait -n || true
    done
    run_case "$pred_len" "$variant" &
  done
done
wait

summary_file="$log_dir/summary.csv"
echo "pred_len,variant,best_val_mse,test_mse,test_mae,coarse_mse,status" > "$summary_file"
for pred_len in "${horizons[@]}"; do
  for variant in "${variants[@]}"; do
    tag="p${pred_len}_${variant}"
    log_file="$log_dir/${tag}.log"
    status_file="$log_dir/${tag}.status"
    status=1
    if [ -f "$status_file" ]; then
      status=$(cat "$status_file")
    fi

    best_val_mse=$(grep '^Best checkpoint validation mse:' "$log_file" 2>/dev/null | tail -n 1 | sed -E 's/.*mse://' || true)
    metric_line=$(grep '^mse:' "$log_file" 2>/dev/null | tail -n 1 || true)
    coarse_line=$(grep '^SRMD coarse-only mse:' "$log_file" 2>/dev/null | tail -n 1 || true)
    test_mse=$(echo "$metric_line" | sed -E 's/.*mse:([^,]+), mae:.*/\1/')
    test_mae=$(echo "$metric_line" | sed -E 's/.*mae:([^ ]+).*/\1/')
    coarse_mse=$(echo "$coarse_line" | sed -E 's/.*mse:([^,]+), mae:.*/\1/')
    echo "$pred_len,$variant,$best_val_mse,$test_mse,$test_mae,$coarse_mse,$status" >> "$summary_file"
  done
done

cat "$summary_file"
