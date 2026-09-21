#!/usr/bin/env bash
set -u

requested_dataset=${1:?Usage: $0 ETTh1|ETTm1|ECL}
gpu_id=${GPU_ID:-0}
export CUDA_VISIBLE_DEVICES="$gpu_id"
script_dir=$(cd "$(dirname "$0")" && pwd)
cd "$script_dir/../.."

case "$requested_dataset" in
  ETTh1)
    dataset_name=ETTh1
    root_path=./dataset/ETT-small/
    data_path=ETTh1.csv
    data_name=ETTh1
    channels=7
    wavelet=db1
    ;;
  ETTm1)
    dataset_name=ETTm1
    root_path=./dataset/ETT-small/
    data_path=ETTm1.csv
    data_name=ETTm1
    channels=7
    wavelet=db1
    ;;
  ECL|ELC)
    dataset_name=ECL
    root_path=./dataset/electricity/
    data_path=electricity.csv
    data_name=custom
    channels=321
    wavelet=db1
    ;;
  *)
    echo "Unsupported dataset: $requested_dataset" >&2
    exit 2
    ;;
esac

log_dir="logs/earmor_grid_v2_${dataset_name}"
mkdir -p "$log_dir"
lock_dir="$log_dir/.run_lock"
if ! mkdir "$lock_dir" 2>/dev/null; then
  echo "${dataset_name} E-Armor grid is already running." >&2
  exit 1
fi
trap 'rmdir "$lock_dir" 2>/dev/null || true' EXIT

summary="$log_dir/summary.csv"
if [ ! -f "$summary" ]; then
  echo "tag,pred_len,d_model,d_ff,e_layers,learning_rate,alpha,m,geomattn_dropout,armor_scale,armor_lr_scale,armor_dropout,armor_cycle,freq,l1_weight,best_val_mse,test_mse,test_mae,status" > "$summary"
fi

run_one() {
  local tag=$1 pred_len=$2 d_model=$3 d_ff=$4 e_layers=$5 learning_rate=$6
  local alpha=$7 levels=$8 geom_dropout=$9 armor_scale=${10} armor_lr_scale=${11}
  local armor_dropout=${12} armor_cycle=${13} run_freq=${14} l1_weight=${15}
  local run_id="${dataset_name}_p${pred_len}_${tag}"
  local log_file="$log_dir/${run_id}.log"
  local status_file="$log_dir/${run_id}.status"

  if [ -f "$log_file" ] && grep -q '^mse:' "$log_file"; then
    echo "GPU ${gpu_id}: skip completed ${run_id}"
  else
    echo "GPU ${gpu_id}: run ${run_id}"
    if python -u run.py \
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
      --num_workers 2 \
      --fix_seed 2025 \
      --use_norm 1 \
      --wv "$wavelet" \
      --m "$levels" \
      --geomattn_dropout "$geom_dropout" \
      --enc_in "$channels" \
      --dec_in "$channels" \
      --c_out "$channels" \
      --des EArmorGridV2 \
      --itr 1 \
      --alpha "$alpha" \
      --l1_weight "$l1_weight" \
      --use_embedding_armor 1 \
      --armor_cycle "$armor_cycle" \
      --armor_scale "$armor_scale" \
      --armor_lr_scale "$armor_lr_scale" \
      --armor_dropout "$armor_dropout" \
      > "$log_file" 2>&1; then
      echo 0 > "$status_file"
    else
      exit_code=$?
      echo "$exit_code" > "$status_file"
    fi
  fi

  local status=1 best_val="" metric_line="" test_mse="" test_mae=""
  if [ -f "$status_file" ]; then
    status=$(cat "$status_file")
  elif grep -q '^mse:' "$log_file" 2>/dev/null; then
    status=0
  fi
  best_val=$(grep '^Best checkpoint validation mse:' "$log_file" 2>/dev/null | tail -n 1 | sed -E 's/.*mse://' || true)
  if [ -z "$best_val" ]; then
    best_val=$(grep 'Validation loss decreased' "$log_file" 2>/dev/null | tail -n 1 | sed -E 's/.*--> ([0-9.eE+-]+)\).*/\1/' || true)
  fi
  metric_line=$(grep '^mse:' "$log_file" 2>/dev/null | tail -n 1 || true)
  if [ -n "$metric_line" ]; then
    test_mse=$(echo "$metric_line" | sed -E 's/.*mse:([^,]+), mae:.*/\1/')
    test_mae=$(echo "$metric_line" | sed -E 's/.*mae:([^ ]+).*/\1/')
  fi

  local temp_summary="$summary.tmp"
  awk -F, -v id="$run_id" 'NR == 1 || $1 != id' "$summary" > "$temp_summary"
  mv "$temp_summary" "$summary"
  echo "${run_id},${pred_len},${d_model},${d_ff},${e_layers},${learning_rate},${alpha},${levels},${geom_dropout},${armor_scale},${armor_lr_scale},${armor_dropout},${armor_cycle},${run_freq},${l1_weight},${best_val},${test_mse},${test_mae},${status}" >> "$summary"
}

for pred_len in 96 192 336 720; do
  base_cycle=24
  base_freq=h
  base_gd=0.5

  case "${dataset_name}_${pred_len}" in
    ETTh1_96)
      base_dm=64; base_ff=64; base_el=1; base_lr=0.02; base_alpha=0.3; base_m=3
      base_l1=0.0005; base_as=1.25; base_alr=1.4; base_ad=0.0
      architectures=("32 64 1" "64 64 1" "64 128 1")
      lr_candidates=(0.016 0.02 0.024); alpha_candidates=(0.1 0.3 0.5)
      m_candidates=(2 3); as_candidates=(1.0 1.25 1.5)
      l1_candidates=(0.0 0.001); cycle_alt=168; freq_alt=h
      ;;
    ETTh1_192)
      base_dm=32; base_ff=32; base_el=1; base_lr=0.02; base_alpha=1.0; base_m=2
      base_l1=0.00005; base_as=0.75; base_alr=1.4; base_ad=0.0
      architectures=("32 32 1" "32 64 1" "64 64 1")
      lr_candidates=(0.016 0.02 0.024); alpha_candidates=(0.75 0.9 1.0)
      m_candidates=(2 3); as_candidates=(0.6 0.75 1.0)
      l1_candidates=(0.0 0.0005); cycle_alt=168; freq_alt=h
      ;;
    ETTh1_336)
      base_dm=64; base_ff=128; base_el=3; base_lr=0.002; base_alpha=0.0; base_m=3
      base_l1=0.0; base_as=1.25; base_alr=1.4; base_ad=0.1
      architectures=("64 128 2" "64 128 3" "96 192 2")
      lr_candidates=(0.0016 0.002 0.0024); alpha_candidates=(0.0 0.1 0.3)
      m_candidates=(2 3); as_candidates=(1.0 1.25 1.5)
      l1_candidates=(0.00005 0.0005); cycle_alt=168; freq_alt=h
      ;;
    ETTh1_720)
      base_dm=64; base_ff=256; base_el=2; base_lr=0.009; base_alpha=0.9; base_m=1
      base_l1=0.0005; base_as=1.25; base_alr=1.4; base_ad=0.0
      architectures=("64 128 2" "64 256 2" "96 192 2")
      lr_candidates=(0.0072 0.009 0.0108); alpha_candidates=(0.75 0.9 1.0)
      m_candidates=(1 2); as_candidates=(1.0 1.25 1.5)
      l1_candidates=(0.0 0.001); cycle_alt=168; freq_alt=h
      ;;

    ETTm1_96)
      base_dm=64; base_ff=128; base_el=3; base_lr=0.02; base_alpha=0.1; base_m=3
      base_l1=0.005; base_as=1.0; base_alr=1.0; base_ad=0.0
      architectures=("32 64 2" "64 64 2" "64 128 3")
      lr_candidates=(0.016 0.02 0.024); alpha_candidates=(0.0 0.1 0.3)
      m_candidates=(2 3); as_candidates=(0.75 1.0 1.25)
      l1_candidates=(0.0005 0.001); cycle_alt=96; freq_alt=t
      ;;
    ETTm1_192)
      base_dm=32; base_ff=64; base_el=2; base_lr=0.02; base_alpha=0.1; base_m=3
      base_l1=0.005; base_as=1.0; base_alr=1.0; base_ad=0.0
      architectures=("32 32 2" "32 64 2" "64 64 1")
      lr_candidates=(0.016 0.02 0.024); alpha_candidates=(0.0 0.1 0.3)
      m_candidates=(2 3); as_candidates=(0.75 1.0 1.25)
      l1_candidates=(0.0005 0.001); cycle_alt=96; freq_alt=t
      ;;
    ETTm1_336)
      base_dm=32; base_ff=32; base_el=1; base_lr=0.02; base_alpha=0.1; base_m=1
      base_l1=0.005; base_as=2.0; base_alr=1.0; base_ad=0.0
      architectures=("32 32 1" "32 64 1" "64 64 1")
      lr_candidates=(0.016 0.02 0.024); alpha_candidates=(0.0 0.1 0.3)
      m_candidates=(1 2); as_candidates=(1.5 2.0 2.5)
      l1_candidates=(0.0005 0.001); cycle_alt=96; freq_alt=t
      ;;
    ETTm1_720)
      base_dm=32; base_ff=32; base_el=1; base_lr=0.02; base_alpha=0.1; base_m=3
      base_l1=0.005; base_as=1.0; base_alr=1.8; base_ad=0.0
      architectures=("32 32 1" "32 128 1" "64 64 1")
      lr_candidates=(0.016 0.02 0.024); alpha_candidates=(0.0 0.1 0.3)
      m_candidates=(2 3); as_candidates=(0.75 1.0 1.25)
      l1_candidates=(0.0005 0.001); cycle_alt=96; freq_alt=t
      ;;

    ECL_96)
      base_dm=256; base_ff=1024; base_el=1; base_lr=0.01; base_alpha=0.0; base_m=3
      base_l1=0.0; base_as=1.0; base_alr=1.0; base_ad=0.0
      architectures=("128 512 1" "256 512 1" "256 1024 1")
      lr_candidates=(0.008 0.01 0.012); alpha_candidates=(0.0 0.1 0.3)
      m_candidates=(2 3); as_candidates=(0.75 1.0 1.25)
      l1_candidates=(0.00005 0.0005); cycle_alt=168; freq_alt=h
      ;;
    ECL_192|ECL_336|ECL_720)
      base_dm=256; base_ff=1024; base_el=1; base_lr=0.006; base_alpha=0.0; base_m=3
      base_as=1.0; base_alr=1.0; base_ad=0.0
      if [ "$pred_len" = 192 ]; then base_l1=0.0; else base_l1=0.00005; fi
      architectures=("128 512 1" "256 512 1" "256 1024 1")
      lr_candidates=(0.0048 0.006 0.0072); alpha_candidates=(0.0 0.1 0.3)
      m_candidates=(2 3); as_candidates=(0.75 1.0 1.25)
      if [ "$base_l1" = 0.0 ]; then l1_candidates=(0.00005 0.0005); else l1_candidates=(0.0 0.0005); fi
      cycle_alt=168; freq_alt=h
      ;;
  esac

  if [ "$base_alr" = 1.8 ]; then
    alr_candidates=(1.4 1.8 2.2)
  else
    alr_candidates=(1.0 1.4 1.8)
  fi
  ad_candidates=(0.0 0.1)
  gd_candidates=(0.35 0.5)

  architecture_id=0
  for architecture in "${architectures[@]}"; do
    architecture_id=$((architecture_id + 1))
    read -r dm ff el <<< "$architecture"
    for lr in "${lr_candidates[@]}"; do
      for armor_scale in "${as_candidates[@]}"; do
        run_one "joint_a${architecture_id}_lr${lr}_as${armor_scale}" \
          "$pred_len" "$dm" "$ff" "$el" "$lr" "$base_alpha" "$base_m" \
          "$base_gd" "$armor_scale" "$base_alr" "$base_ad" "$base_cycle" \
          "$base_freq" "$base_l1"
      done
    done
  done

  for alpha in "${alpha_candidates[@]}"; do
    for levels in "${m_candidates[@]}"; do
      for geom_dropout in "${gd_candidates[@]}"; do
        if [ "$alpha" = "$base_alpha" ] && [ "$levels" = "$base_m" ] && \
           [ "$geom_dropout" = "$base_gd" ]; then
          continue
        fi
        run_one "amg_a${alpha}_m${levels}_gd${geom_dropout}" \
          "$pred_len" "$base_dm" "$base_ff" "$base_el" "$base_lr" "$alpha" \
          "$levels" "$geom_dropout" "$base_as" "$base_alr" "$base_ad" \
          "$base_cycle" "$base_freq" "$base_l1"
      done
    done
  done

  for armor_lr in "${alr_candidates[@]}"; do
    for armor_dropout in "${ad_candidates[@]}"; do
      if [ "$armor_lr" = "$base_alr" ] && [ "$armor_dropout" = "$base_ad" ]; then
        continue
      fi
      run_one "armor_alr${armor_lr}_ad${armor_dropout}" \
        "$pred_len" "$base_dm" "$base_ff" "$base_el" "$base_lr" "$base_alpha" \
        "$base_m" "$base_gd" "$base_as" "$armor_lr" "$armor_dropout" \
        "$base_cycle" "$base_freq" "$base_l1"
    done
  done

  for l1_weight in "${l1_candidates[@]}"; do
    run_one "l1_${l1_weight}" \
      "$pred_len" "$base_dm" "$base_ff" "$base_el" "$base_lr" "$base_alpha" \
      "$base_m" "$base_gd" "$base_as" "$base_alr" "$base_ad" \
      "$base_cycle" "$base_freq" "$l1_weight"
  done
  run_one "cycle${cycle_alt}_${freq_alt}" \
    "$pred_len" "$base_dm" "$base_ff" "$base_el" "$base_lr" "$base_alpha" \
    "$base_m" "$base_gd" "$base_as" "$base_alr" "$base_ad" \
    "$cycle_alt" "$freq_alt" "$base_l1"
done

{
  head -n 1 "$summary"
  awk -F, '$19 == 0 && $16 != ""' "$summary" | sort -t, -k2,2n -k16,16g
} > "$log_dir/summary_by_validation.csv"
{
  head -n 1 "$summary"
  awk -F, '$19 == 0 && $17 != ""' "$summary" | sort -t, -k2,2n -k17,17g
} > "$log_dir/summary_by_test_diagnostic.csv"

echo "${dataset_name} E-Armor grid complete on physical GPU ${gpu_id}."
echo "Formal ranking: $log_dir/summary_by_validation.csv"
