#!/usr/bin/env bash
set -u

dataset_name=${1:?Usage: $0 ETTh1|ETTm1|Weather}
gpu_id=${GPU_ID:-0}
export CUDA_VISIBLE_DEVICES="$gpu_id"
script_dir=$(cd "$(dirname "$0")" && pwd)
cd "$script_dir/../.."

case "$dataset_name" in
  ETTh1)
    root_path=./dataset/ETT-small/
    data_path=ETTh1.csv
    data_name=ETTh1
    frequency=h
    channels=7
    wavelet=db1
    ;;
  ETTm1)
    root_path=./dataset/ETT-small/
    data_path=ETTm1.csv
    data_name=ETTm1
    frequency=h
    channels=7
    wavelet=db1
    ;;
  Weather)
    root_path=./dataset/weather/
    data_path=weather.csv
    data_name=custom
    frequency=h
    channels=21
    wavelet=db4
    ;;
  *)
    echo "Unsupported dataset: $dataset_name" >&2
    exit 2
    ;;
esac

log_dir="logs/night_grid_${dataset_name}"
summary="$log_dir/summary.csv"
mkdir -p "$log_dir"
if [ ! -f "$summary" ]; then
  echo "tag,pred_len,d_model,d_ff,e_layers,learning_rate,alpha,m,geomattn_dropout,armor_scale,armor_lr_scale,armor_dropout,armor_cycle,freq,mse,mae,status" > "$summary"
fi

run_one() {
  local tag=$1 pred_len=$2 d_model=$3 d_ff=$4 e_layers=$5 learning_rate=$6
  local alpha=$7 levels=$8 geom_dropout=$9 armor_scale=${10} armor_lr_scale=${11}
  local armor_dropout=${12} armor_cycle=${13} run_freq=${14} l1_weight=${15}
  local run_id="${dataset_name}_p${pred_len}_${tag}"
  local log_file="$log_dir/${run_id}.log"

  if [ -f "$log_file" ] && grep -q '^mse:' "$log_file"; then
    echo "Skip completed: $run_id"
  else
    echo "Run: $run_id on GPU $gpu_id"
    python -u run.py \
      --is_training 1 \
      --lradj TST \
      --train_epochs 10 \
      --patience 3 \
      --root_path "$root_path" \
      --data_path "$data_path" \
      --model_id "$run_id" \
      --model SimpleTM \
      --data "$data_name" \
      --features M \
      --freq "$run_freq" \
      --seq_len 96 \
      --pred_len "$pred_len" \
      --e_layers "$e_layers" \
      --d_model "$d_model" \
      --d_ff "$d_ff" \
      --learning_rate "$learning_rate" \
      --weight_decay 0.01 \
      --batch_size 256 \
      --fix_seed 2025 \
      --use_norm 1 \
      --wv "$wavelet" \
      --m "$levels" \
      --geomattn_dropout "$geom_dropout" \
      --enc_in "$channels" \
      --dec_in "$channels" \
      --c_out "$channels" \
      --des NightGrid \
      --itr 1 \
      --alpha "$alpha" \
      --l1_weight "$l1_weight" \
      --use_embedding_armor 1 \
      --armor_cycle "$armor_cycle" \
      --armor_scale "$armor_scale" \
      --armor_lr_scale "$armor_lr_scale" \
      --armor_dropout "$armor_dropout" \
      > "$log_file" 2>&1
  fi

  local status=0 metrics
  metrics=$(sed -n 's/^mse:\([^,]*\), mae:\(.*\)$/\1,\2/p' "$log_file" | tail -n 1)
  if [ -z "$metrics" ]; then
    status=1
    metrics=","
  fi
  if ! grep -q "^${run_id}," "$summary"; then
    echo "${run_id},${pred_len},${d_model},${d_ff},${e_layers},${learning_rate},${alpha},${levels},${geom_dropout},${armor_scale},${armor_lr_scale},${armor_dropout},${armor_cycle},${run_freq},${metrics},${status}" >> "$summary"
  fi
}

for pred_len in 96 192 336 720; do
  case "${dataset_name}_${pred_len}" in
    ETTh1_96)  base_dm=32; base_ff=32; base_el=1; base_lr=0.02;  base_alpha=0.3; base_m=3; base_l1=0.0005;  base_as=1.25; base_alr=1.4; base_ad=0.0 ;;
    ETTh1_192) base_dm=32; base_ff=32; base_el=1; base_lr=0.02;  base_alpha=1.0; base_m=3; base_l1=0.00005; base_as=0.75; base_alr=1.4; base_ad=0.0 ;;
    ETTh1_336) base_dm=64; base_ff=64; base_el=4; base_lr=0.002; base_alpha=0.0; base_m=3; base_l1=0.0;     base_as=1.25; base_alr=1.4; base_ad=0.1 ;;
    ETTh1_720) base_dm=32; base_ff=32; base_el=1; base_lr=0.009; base_alpha=0.9; base_m=1; base_l1=0.0005;  base_as=1.25; base_alr=1.4; base_ad=0.0 ;;

    ETTm1_96|ETTm1_192) base_dm=32; base_ff=32; base_el=1; base_lr=0.02; base_alpha=0.1; base_m=3; base_l1=0.005; base_as=1.0; base_alr=1.0; base_ad=0.0 ;;
    ETTm1_336)           base_dm=32; base_ff=32; base_el=1; base_lr=0.02; base_alpha=0.1; base_m=1; base_l1=0.005; base_as=1.0; base_alr=1.0; base_ad=0.0 ;;
    ETTm1_720)           base_dm=32; base_ff=32; base_el=1; base_lr=0.02; base_alpha=0.1; base_m=3; base_l1=0.005; base_as=1.0; base_alr=1.0; base_ad=0.0 ;;

    Weather_96)  base_dm=32; base_ff=32; base_el=4; base_lr=0.01;  base_alpha=0.3; base_m=1; base_l1=0.00005; base_as=1.0; base_alr=1.0; base_ad=0.0 ;;
    Weather_192) base_dm=32; base_ff=32; base_el=4; base_lr=0.009; base_alpha=0.3; base_m=1; base_l1=0.0;     base_as=1.0; base_alr=1.0; base_ad=0.0 ;;
    Weather_336) base_dm=32; base_ff=32; base_el=1; base_lr=0.009; base_alpha=1.0; base_m=3; base_l1=0.00005; base_as=1.0; base_alr=1.0; base_ad=0.0 ;;
    Weather_720) base_dm=32; base_ff=32; base_el=1; base_lr=0.02;  base_alpha=0.9; base_m=1; base_l1=0.005;   base_as=1.0; base_alr=1.0; base_ad=0.0 ;;
  esac

  base_cycle=24
  run_one base "$pred_len" "$base_dm" "$base_ff" "$base_el" "$base_lr" "$base_alpha" "$base_m" 0.5 "$base_as" "$base_alr" "$base_ad" "$base_cycle" "$frequency" "$base_l1"

  architecture_profiles=(
    "16 16 1" "16 32 1" "32 32 1" "32 64 1" "32 128 1"
    "32 64 2" "64 64 1" "64 128 1" "64 64 2"
    "64 128 2" "64 128 3" "64 256 1" "64 256 2"
    "96 192 1" "96 96 2" "96 192 2" "128 256 1" "128 256 2"
  )
  profile_id=0
  for profile in "${architecture_profiles[@]}"; do
    profile_id=$((profile_id + 1))
    read -r dm ff el <<< "$profile"
    if [ "$dm" = "$base_dm" ] && [ "$ff" = "$base_ff" ] && [ "$el" = "$base_el" ]; then
      continue
    fi
    run_one "arch${profile_id}" "$pred_len" "$dm" "$ff" "$el" "$base_lr" "$base_alpha" "$base_m" 0.5 "$base_as" "$base_alr" "$base_ad" "$base_cycle" "$frequency" "$base_l1"
  done

  case "$base_lr" in
    0.02)  lr_low=0.014;  lr_mid_low=0.017;   lr_mid_high=0.023;   lr_high=0.028 ;;
    0.01)  lr_low=0.007;  lr_mid_low=0.0085;  lr_mid_high=0.0115;  lr_high=0.014 ;;
    0.009) lr_low=0.0063; lr_mid_low=0.00765; lr_mid_high=0.01035; lr_high=0.0126 ;;
    0.002) lr_low=0.0014; lr_mid_low=0.0017;  lr_mid_high=0.0023;  lr_high=0.0028 ;;
  esac
  run_one lr_low  "$pred_len" "$base_dm" "$base_ff" "$base_el" "$lr_low"  "$base_alpha" "$base_m" 0.5 "$base_as" "$base_alr" "$base_ad" "$base_cycle" "$frequency" "$base_l1"
  run_one lr_mid_low "$pred_len" "$base_dm" "$base_ff" "$base_el" "$lr_mid_low" "$base_alpha" "$base_m" 0.5 "$base_as" "$base_alr" "$base_ad" "$base_cycle" "$frequency" "$base_l1"
  run_one lr_mid_high "$pred_len" "$base_dm" "$base_ff" "$base_el" "$lr_mid_high" "$base_alpha" "$base_m" 0.5 "$base_as" "$base_alr" "$base_ad" "$base_cycle" "$frequency" "$base_l1"
  run_one lr_high "$pred_len" "$base_dm" "$base_ff" "$base_el" "$lr_high" "$base_alpha" "$base_m" 0.5 "$base_as" "$base_alr" "$base_ad" "$base_cycle" "$frequency" "$base_l1"

  for value in 0.0 0.1 0.2 0.3 0.45 0.6 0.75 0.9 1.0; do
    [ "$value" = "$base_alpha" ] && continue
    run_one "alpha${value}" "$pred_len" "$base_dm" "$base_ff" "$base_el" "$base_lr" "$value" "$base_m" 0.5 "$base_as" "$base_alr" "$base_ad" "$base_cycle" "$frequency" "$base_l1"
  done
  for value in 1 2 3 4; do
    [ "$value" = "$base_m" ] && continue
    run_one "m${value}" "$pred_len" "$base_dm" "$base_ff" "$base_el" "$base_lr" "$base_alpha" "$value" 0.5 "$base_as" "$base_alr" "$base_ad" "$base_cycle" "$frequency" "$base_l1"
  done
  for value in 0.25 0.35 0.65 0.75; do
    run_one "gd${value}" "$pred_len" "$base_dm" "$base_ff" "$base_el" "$base_lr" "$base_alpha" "$base_m" "$value" "$base_as" "$base_alr" "$base_ad" "$base_cycle" "$frequency" "$base_l1"
  done
  for value in 0.75 1.0 1.25 1.5 1.75 2.0; do
    [ "$value" = "$base_as" ] && continue
    run_one "as${value}" "$pred_len" "$base_dm" "$base_ff" "$base_el" "$base_lr" "$base_alpha" "$base_m" 0.5 "$value" "$base_alr" "$base_ad" "$base_cycle" "$frequency" "$base_l1"
  done
  for value in 0.8 1.0 1.4 1.8 2.2; do
    [ "$value" = "$base_alr" ] && continue
    run_one "alr${value}" "$pred_len" "$base_dm" "$base_ff" "$base_el" "$base_lr" "$base_alpha" "$base_m" 0.5 "$base_as" "$value" "$base_ad" "$base_cycle" "$frequency" "$base_l1"
  done
  for value in 0.0 0.05 0.1 0.15; do
    [ "$value" = "$base_ad" ] && continue
    run_one "ad${value}" "$pred_len" "$base_dm" "$base_ff" "$base_el" "$base_lr" "$base_alpha" "$base_m" 0.5 "$base_as" "$base_alr" "$value" "$base_cycle" "$frequency" "$base_l1"
  done

  if [ "$dataset_name" = ETTm1 ]; then
    run_one cycle96 "$pred_len" "$base_dm" "$base_ff" "$base_el" "$base_lr" "$base_alpha" "$base_m" 0.5 "$base_as" "$base_alr" "$base_ad" 96 t "$base_l1"
  else
    run_one cycle168 "$pred_len" "$base_dm" "$base_ff" "$base_el" "$base_lr" "$base_alpha" "$base_m" 0.5 "$base_as" "$base_alr" "$base_ad" 168 h "$base_l1"
  fi
done

echo "Night grid complete: $summary"
