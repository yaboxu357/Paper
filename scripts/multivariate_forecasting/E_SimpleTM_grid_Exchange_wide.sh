#!/usr/bin/env bash
set -u

gpu_id=${GPU_ID:-0}
export CUDA_VISIBLE_DEVICES="$gpu_id"
script_dir=$(cd "$(dirname "$0")" && pwd)
cd "$script_dir/../.."

if [ -f ./exchange_rate/exchange_rate.csv ]; then
  root_path=./exchange_rate/
else
  root_path=./dataset/exchange_rate/
fi
if [ ! -f "${root_path}exchange_rate.csv" ]; then
  echo "Exchange data not found at ./exchange_rate/exchange_rate.csv or ./dataset/exchange_rate/exchange_rate.csv" >&2
  exit 2
fi

log_dir=logs/esimpletm_grid_exchange_wide
summary="$log_dir/summary.csv"
mkdir -p "$log_dir"
lock_dir="$log_dir/.run_lock"
if ! mkdir "$lock_dir" 2>/dev/null; then
  echo "Exchange wide grid is already running" >&2
  exit 1
fi
trap 'rmdir "$lock_dir" 2>/dev/null || true' EXIT

if [ ! -f "$summary" ]; then
  echo "tag,pred_len,d_model,d_ff,e_layers,learning_rate,wavelet,alpha,m,geomattn_dropout,armor_scale,armor_lr_scale,armor_dropout,armor_cycle,l1_weight,weight_decay,batch_size,use_norm,dropout,mse,mae,status" > "$summary"
fi

run_one() {
  local tag=$1 pred_len=$2 d_model=$3 d_ff=$4 e_layers=$5 learning_rate=$6
  local wavelet=$7 alpha=$8 levels=$9 geom_dropout=${10} armor_scale=${11}
  local armor_lr_scale=${12} armor_dropout=${13} armor_cycle=${14} l1_weight=${15}
  local weight_decay=${16} batch_size=${17} use_norm=${18} dropout=${19}
  local run_id="Exchange_p${pred_len}_${tag}"
  local log_file="$log_dir/${run_id}.log"
  local status_file="$log_dir/${run_id}.status"

  if [ -f "$status_file" ] && [ "$(cat "$status_file")" = 0 ] && grep -q '^mse:' "$log_file"; then
    echo "GPU $gpu_id: skip completed $run_id"
    return
  fi

  echo "GPU $gpu_id: run $run_id"
  python -u run.py \
    --is_training 1 \
    --lradj TST \
    --train_epochs 10 \
    --patience 3 \
    --root_path "$root_path" \
    --data_path exchange_rate.csv \
    --model_id "$run_id" \
    --model SimpleTM \
    --data custom \
    --features M \
    --freq d \
    --seq_len 96 \
    --pred_len "$pred_len" \
    --e_layers "$e_layers" \
    --d_model "$d_model" \
    --d_ff "$d_ff" \
    --dropout "$dropout" \
    --learning_rate "$learning_rate" \
    --weight_decay "$weight_decay" \
    --batch_size "$batch_size" \
    --num_workers 2 \
    --fix_seed 2025 \
    --use_norm "$use_norm" \
    --wv "$wavelet" \
    --m "$levels" \
    --geomattn_dropout "$geom_dropout" \
    --enc_in 8 \
    --dec_in 8 \
    --c_out 8 \
    --des ESimpleTMExchangeWide \
    --itr 1 \
    --alpha "$alpha" \
    --l1_weight "$l1_weight" \
    --use_embedding_armor 1 \
    --armor_cycle "$armor_cycle" \
    --armor_scale "$armor_scale" \
    --armor_lr_scale "$armor_lr_scale" \
    --armor_dropout "$armor_dropout" \
    > "$log_file" 2>&1
  local status=$?
  echo "$status" > "$status_file"

  local metrics
  metrics=$(sed -n 's/^mse:\([^,]*\), mae:\(.*\)$/\1,\2/p' "$log_file" | tail -n 1)
  if [ -z "$metrics" ]; then
    metrics=","
  fi
  local temp_summary="$summary.tmp"
  awk -F, -v id="$run_id" 'NR == 1 || $1 != id' "$summary" > "$temp_summary"
  mv "$temp_summary" "$summary"
  echo "${run_id},${pred_len},${d_model},${d_ff},${e_layers},${learning_rate},${wavelet},${alpha},${levels},${geom_dropout},${armor_scale},${armor_lr_scale},${armor_dropout},${armor_cycle},${l1_weight},${weight_decay},${batch_size},${use_norm},${dropout},${metrics},${status}" >> "$summary"
}

architectures=(
  "16 16 1" "16 32 2" "32 32 1" "32 64 2"
  "64 64 1" "64 128 2" "128 128 1" "128 256 2"
  "128 256 4" "256 256 1" "256 512 2" "384 512 2" "512 1024 3"
)
learning_rates=(0.00005 0.0001 0.0002 0.0005 0.001 0.002 0.005 0.01)
alphas=(0.0 0.1 0.2 0.3 0.45 0.6 0.75 0.9 1.0)
levels=(1 2 3 4 5)
geom_dropouts=(0.25 0.5 0.75)
wavelets=(db1 db2 db4 db8 bior3.1 bior3.3 sym2)
armor_scales=(0.25 0.5 0.75 1.0 1.25 1.5 2.0 2.5)
armor_lr_scales=(0.3 0.5 0.8 1.0 1.4 2.0 3.0)
armor_dropouts=(0.05 0.1 0.2 0.3 0.4)
l1_values=(0.0 0.00005 0.0001 0.0005 0.001 0.005)
weight_decays=(0.0 0.001 0.005 0.01 0.05)
batch_sizes=(32 64 128 256)
norm_values=(0 1)
model_dropouts=(0.0 0.05 0.1 0.2 0.3)
cycle_values=(1 7 24 32)

for pred_len in 96 192 336 720; do
  # Best completed test configuration; subsequent families search around it.
  case "$pred_len" in
    96)  ref_dm=384; ref_ff=512; ref_el=2; ref_lr=0.0002 ;;
    192) ref_dm=128; ref_ff=128; ref_el=1; ref_lr=0.001 ;;
    336) ref_dm=384; ref_ff=512; ref_el=2; ref_lr=0.01 ;;
    720) ref_dm=256; ref_ff=512; ref_el=2; ref_lr=0.002 ;;
  esac
  ref_wv=db1; ref_alpha=0.3; ref_m=3; ref_gd=0.5
  ref_as=1.0; ref_alr=1.0; ref_ad=0.0; ref_cycle=7
  ref_l1=0.00005; ref_wd=0.01; ref_bs=128; ref_norm=1; ref_dropout=0.1

  run_one ref "$pred_len" "$ref_dm" "$ref_ff" "$ref_el" "$ref_lr" "$ref_wv" "$ref_alpha" "$ref_m" "$ref_gd" "$ref_as" "$ref_alr" "$ref_ad" "$ref_cycle" "$ref_l1" "$ref_wd" "$ref_bs" "$ref_norm" "$ref_dropout"

  arch_id=0
  for architecture in "${architectures[@]}"; do
    arch_id=$((arch_id + 1))
    read -r dm ff el <<< "$architecture"
    for lr in "${learning_rates[@]}"; do
      run_one "archlr_a${arch_id}_lr${lr}" "$pred_len" "$dm" "$ff" "$el" "$lr" "$ref_wv" "$ref_alpha" "$ref_m" "$ref_gd" "$ref_as" "$ref_alr" "$ref_ad" "$ref_cycle" "$ref_l1" "$ref_wd" "$ref_bs" "$ref_norm" "$ref_dropout"
    done
  done

  for alpha in "${alphas[@]}"; do
    for level in "${levels[@]}"; do
      for geom_dropout in "${geom_dropouts[@]}"; do
        if [ "$alpha" = "$ref_alpha" ] && [ "$level" = "$ref_m" ] && [ "$geom_dropout" = "$ref_gd" ]; then
          continue
        fi
        run_one "amg_a${alpha}_m${level}_gd${geom_dropout}" "$pred_len" "$ref_dm" "$ref_ff" "$ref_el" "$ref_lr" "$ref_wv" "$alpha" "$level" "$geom_dropout" "$ref_as" "$ref_alr" "$ref_ad" "$ref_cycle" "$ref_l1" "$ref_wd" "$ref_bs" "$ref_norm" "$ref_dropout"
      done
    done
  done

  for wavelet in "${wavelets[@]}"; do
    for level in "${levels[@]}"; do
      if [ "$wavelet" = "$ref_wv" ] && [ "$level" = "$ref_m" ]; then
        continue
      fi
      run_one "wave_${wavelet}_m${level}" "$pred_len" "$ref_dm" "$ref_ff" "$ref_el" "$ref_lr" "$wavelet" "$ref_alpha" "$level" "$ref_gd" "$ref_as" "$ref_alr" "$ref_ad" "$ref_cycle" "$ref_l1" "$ref_wd" "$ref_bs" "$ref_norm" "$ref_dropout"
    done
  done

  for armor_scale in "${armor_scales[@]}"; do
    for armor_lr_scale in "${armor_lr_scales[@]}"; do
      if [ "$armor_scale" = "$ref_as" ] && [ "$armor_lr_scale" = "$ref_alr" ]; then
        continue
      fi
      run_one "armor_lr_as${armor_scale}_alr${armor_lr_scale}" "$pred_len" "$ref_dm" "$ref_ff" "$ref_el" "$ref_lr" "$ref_wv" "$ref_alpha" "$ref_m" "$ref_gd" "$armor_scale" "$armor_lr_scale" 0.0 "$ref_cycle" "$ref_l1" "$ref_wd" "$ref_bs" "$ref_norm" "$ref_dropout"
    done
    for armor_dropout in "${armor_dropouts[@]}"; do
      run_one "armor_drop_as${armor_scale}_ad${armor_dropout}" "$pred_len" "$ref_dm" "$ref_ff" "$ref_el" "$ref_lr" "$ref_wv" "$ref_alpha" "$ref_m" "$ref_gd" "$armor_scale" "$ref_alr" "$armor_dropout" "$ref_cycle" "$ref_l1" "$ref_wd" "$ref_bs" "$ref_norm" "$ref_dropout"
    done
  done

  for l1_weight in "${l1_values[@]}"; do
    for weight_decay in "${weight_decays[@]}"; do
      if [ "$l1_weight" = "$ref_l1" ] && [ "$weight_decay" = "$ref_wd" ]; then
        continue
      fi
      run_one "reg_l1${l1_weight}_wd${weight_decay}" "$pred_len" "$ref_dm" "$ref_ff" "$ref_el" "$ref_lr" "$ref_wv" "$ref_alpha" "$ref_m" "$ref_gd" "$ref_as" "$ref_alr" "$ref_ad" "$ref_cycle" "$l1_weight" "$weight_decay" "$ref_bs" "$ref_norm" "$ref_dropout"
    done
  done

  for batch_size in "${batch_sizes[@]}"; do
    for use_norm in "${norm_values[@]}"; do
      for dropout in "${model_dropouts[@]}"; do
        if [ "$batch_size" = "$ref_bs" ] && [ "$use_norm" = "$ref_norm" ] && [ "$dropout" = "$ref_dropout" ]; then
          continue
        fi
        run_one "train_bs${batch_size}_n${use_norm}_d${dropout}" "$pred_len" "$ref_dm" "$ref_ff" "$ref_el" "$ref_lr" "$ref_wv" "$ref_alpha" "$ref_m" "$ref_gd" "$ref_as" "$ref_alr" "$ref_ad" "$ref_cycle" "$ref_l1" "$ref_wd" "$batch_size" "$use_norm" "$dropout"
      done
    done
  done

  for cycle in "${cycle_values[@]}"; do
    [ "$cycle" = "$ref_cycle" ] && continue
    run_one "cycle${cycle}" "$pred_len" "$ref_dm" "$ref_ff" "$ref_el" "$ref_lr" "$ref_wv" "$ref_alpha" "$ref_m" "$ref_gd" "$ref_as" "$ref_alr" "$ref_ad" "$cycle" "$ref_l1" "$ref_wd" "$ref_bs" "$ref_norm" "$ref_dropout"
  done
done

echo "Exchange wide grid complete: $summary"
