#!/usr/bin/env bash
set -u

script_dir=$(cd "$(dirname "$0")" && pwd)
project_root=$(cd "$script_dir/../../.." && pwd)
cd "$project_root"

log_dir=logs/lrhyperhead_etth1_stage1
mkdir -p "$log_dir"
lock_dir="$log_dir/.run_lock"
if ! mkdir "$lock_dir" 2>/dev/null; then
  echo "LR-HyperHead stage 1 is already running; refusing to overwrite logs." >&2
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
modes=(primary auxiliary)

run_case() {
  pred_len=$1
  mode=$2

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

  tag="p${pred_len}_${mode}"
  log_file="$log_dir/${tag}.log"
  status_file="$log_dir/${tag}.status"
  echo "GPU 0: starting ${tag}"

  if CUDA_VISIBLE_DEVICES=0 python -u run.py \
    --is_training 1 \
    --root_path ./dataset/ETT-small/ \
    --data_path ETTh1.csv \
    --model_id "ETTh1_LRHyperHead_${tag}" \
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
    --use_hyperhead 1 \
    --hyper_mode "$mode" \
    --hyper_rank 8 \
    --hyper_embedding_dim 8 \
    --hyper_hidden 32 \
    --hyper_scale_init 0.05 \
    --hyper_dropout 0.0 \
    --hyper_aux_weight 0.25 \
    --hyper_warmup_epochs 2.0 \
    --hyper_lr_scale 0.5 \
    --batch_size 256 \
    --num_workers 2 \
    --train_epochs 10 \
    --patience 3 \
    --lradj TST \
    --pct_start 0.2 \
    --weight_decay 0.01 \
    --fix_seed 2025 \
    --des LRHyperHead_Stage1 \
    --gpu 0 > "$log_file" 2>&1; then
    echo 0 > "$status_file"
  else
    exit_code=$?
    echo "$exit_code" > "$status_file"
  fi
  echo "GPU 0: finished ${tag} (status $(cat "$status_file"))"
}

for pred_len in "${horizons[@]}"; do
  for mode in "${modes[@]}"; do
    while [ "$(jobs -pr | wc -l)" -ge "$max_jobs" ]; do
      wait -n || true
    done
    run_case "$pred_len" "$mode" &
  done
done
wait

summary_file="$log_dir/summary.csv"
echo "pred_len,mode,best_val_mse,test_mse,test_mae,shared_mse,generated_mse,status" > "$summary_file"
for pred_len in "${horizons[@]}"; do
  for mode in "${modes[@]}"; do
    tag="p${pred_len}_${mode}"
    log_file="$log_dir/${tag}.log"
    status_file="$log_dir/${tag}.status"
    status=1
    if [ -f "$status_file" ]; then
      status=$(cat "$status_file")
    fi

    best_val_mse=$(grep '^Best checkpoint validation mse:' "$log_file" 2>/dev/null | tail -n 1 | sed -E 's/.*mse://' || true)
    metric_line=$(grep '^mse:' "$log_file" 2>/dev/null | tail -n 1 || true)
    shared_line=$(grep '^HyperHead shared mse:' "$log_file" 2>/dev/null | tail -n 1 || true)
    generated_line=$(grep '^HyperHead generated mse:' "$log_file" 2>/dev/null | tail -n 1 || true)
    test_mse=$(echo "$metric_line" | sed -E 's/.*mse:([^,]+), mae:.*/\1/')
    test_mae=$(echo "$metric_line" | sed -E 's/.*mae:([^ ]+).*/\1/')
    shared_mse=$(echo "$shared_line" | sed -E 's/.*mse:([^,]+), mae:.*/\1/')
    generated_mse=$(echo "$generated_line" | sed -E 's/.*mse:([^,]+), mae:.*/\1/')
    echo "$pred_len,$mode,$best_val_mse,$test_mse,$test_mae,$shared_mse,$generated_mse,$status" >> "$summary_file"
  done
done

cat "$summary_file"
