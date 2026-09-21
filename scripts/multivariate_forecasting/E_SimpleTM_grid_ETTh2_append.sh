#!/usr/bin/env bash
set -u

script_dir=$(cd "$(dirname "$0")" && pwd)
project_root=$(cd "$script_dir/../.." && pwd)
cd "$project_root"

gpu_id=${GPU_ID:-0}
max_jobs=${MAX_JOBS:-8}
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
export CUDA_VISIBLE_DEVICES="$gpu_id"

log_dir=logs/esimpletm_grid_expanded_ETTh2
summary="$log_dir/summary.csv"
manifest="$log_dir/.append_v2_manifest.csv"
seen_file="$log_dir/.append_v2_seen"
lock_dir="$log_dir/.append_v2_run_lock"
mkdir -p "$log_dir"

if [ -d "$log_dir/.run_lock" ]; then
  echo "The original ETTh2 grid still holds $log_dir/.run_lock; stop or finish it first." >&2
  exit 1
fi
if ! mkdir "$lock_dir" 2>/dev/null; then
  echo "The ETTh2 append grid is already running: $lock_dir" >&2
  exit 1
fi
trap 'rm -f "$seen_file" "$manifest"; rmdir "$lock_dir" 2>/dev/null || true' EXIT

summary_header='tag,pred_len,d_model,d_ff,e_layers,learning_rate,wavelet,alpha,m,geomattn_dropout,armor_scale,armor_lr_scale,armor_dropout,armor_cycle,freq,l1_weight,weight_decay,mse,mae,status'
manifest_header='tag,pred_len,d_model,d_ff,e_layers,learning_rate,wavelet,alpha,m,geomattn_dropout,armor_scale,armor_lr_scale,armor_dropout,armor_cycle,freq,use_norm,l1_weight,weight_decay,mse,mae,status'
if [ ! -f "$summary" ]; then
  echo "$summary_header" > "$summary"
fi

# Canonical signatures let the extension skip configurations already present in
# the original grid even when equivalent numbers use different text formatting.
awk -F, '
  NR > 1 {
    if (NF >= 21) {
      norm=$16; l1=$17; wd=$18
    } else {
      norm=1; l1=$16; wd=$17
    }
    printf "%.12g|%.12g|%.12g|%.12g|%.12g|%s|%.12g|%.12g|%.12g|%.12g|%.12g|%.12g|%.12g|%s|%.12g|%.12g|%.12g\n",
      $2+0,$3+0,$4+0,$5+0,$6+0,$7,$8+0,$9+0,$10+0,$11+0,$12+0,$13+0,$14+0,$15,norm+0,l1+0,wd+0
  }
' "$summary" | sort -u > "$seen_file"

echo "$manifest_header" > "$manifest"
candidate_count=0

signature() {
  awk -v p="$1" -v dm="$2" -v ff="$3" -v el="$4" -v lr="$5" -v wv="$6" \
      -v a="$7" -v m="$8" -v gd="$9" -v as="${10}" -v alr="${11}" \
      -v ad="${12}" -v cy="${13}" -v fr="${14}" -v norm="${15}" \
      -v l1="${16}" -v wd="${17}" \
      'BEGIN {printf "%.12g|%.12g|%.12g|%.12g|%.12g|%s|%.12g|%.12g|%.12g|%.12g|%.12g|%.12g|%.12g|%s|%.12g|%.12g|%.12g", p+0,dm+0,ff+0,el+0,lr+0,wv,a+0,m+0,gd+0,as+0,alr+0,ad+0,cy+0,fr,norm+0,l1+0,wd+0}'
}

add_candidate() {
  local pred_len=$1 d_model=$2 d_ff=$3 e_layers=$4 learning_rate=$5
  local wavelet=$6 alpha=$7 levels=$8 geom_dropout=$9 armor_scale=${10}
  local armor_lr_scale=${11} armor_dropout=${12} armor_cycle=${13} run_freq=${14}
  local normalization=${15} l1_weight=${16} weight_decay=${17} family=${18}
  local sig run_id

  sig=$(signature "$pred_len" "$d_model" "$d_ff" "$e_layers" "$learning_rate" \
    "$wavelet" "$alpha" "$levels" "$geom_dropout" "$armor_scale" \
    "$armor_lr_scale" "$armor_dropout" "$armor_cycle" "$run_freq" \
    "$normalization" "$l1_weight" "$weight_decay")
  if grep -Fxq "$sig" "$seen_file"; then
    return
  fi

  candidate_count=$((candidate_count + 1))
  run_id="ETTh2_p${pred_len}_x2_${family}_${candidate_count}"
  echo "$sig" >> "$seen_file"
  echo "${run_id},${pred_len},${d_model},${d_ff},${e_layers},${learning_rate},${wavelet},${alpha},${levels},${geom_dropout},${armor_scale},${armor_lr_scale},${armor_dropout},${armor_cycle},${run_freq},${normalization},${l1_weight},${weight_decay},,," >> "$manifest"
}

set_anchor() {
  case "$1" in
    96)
      base_dm=32; base_ff=32; base_el=1; base_lr=0.006; base_wv=bior3.1
      base_alpha=0.1; base_m=3; base_gd=0.5; base_as=0.75
      base_alr=2.0; base_ad=0.2; base_l1=0.0005; base_wd=0.01
      arch_profiles=('24 32 1' '32 48 1' '32 64 1' '48 64 1' '48 96 1' '64 128 1')
      lr_values=(0.0048 0.0054 0.0063 0.0072)
      alpha_values=(0.0 0.05 0.15 0.25)
      scale_values=(0.35 0.55 0.85 1.1)
      alr_values=(1.4 2.5)
      fusion_profiles=('32 64 1' '64 128 1')
      fusion_lrs=(0.0054 0.0063)
      fusion_alphas=(0.05 0.15)
      fusion_scales=(0.55 0.85)
      fusion_gd=0.25; fusion_alr=2.5; fusion_ad=0.1; fusion_l1=0.0001; fusion_wd=0.005
      reg_ad_values=(0.05 0.1 0.15)
      reg_l1_values=(0.0 0.0001 0.001)
      ;;
    192)
      base_dm=32; base_ff=32; base_el=1; base_lr=0.0069; base_wv=db1
      base_alpha=0.1; base_m=1; base_gd=0.5; base_as=1.0
      base_alr=1.0; base_ad=0.0; base_l1=0.005; base_wd=0.01
      arch_profiles=('24 32 1' '32 48 1' '32 64 1' '48 64 1' '64 64 1' '64 128 1')
      lr_values=(0.0063 0.0066 0.0072 0.0075)
      alpha_values=(0.0 0.05 0.15 0.25)
      scale_values=(0.1 0.2 0.35 0.5)
      alr_values=(0.3 0.7)
      fusion_profiles=('32 64 1' '64 64 1')
      fusion_lrs=(0.0066 0.0072)
      fusion_alphas=(0.05 0.15)
      fusion_scales=(0.2 0.4)
      fusion_gd=0.35; fusion_alr=0.5; fusion_ad=0.05; fusion_l1=0.0025; fusion_wd=0.005
      reg_ad_values=(0.05 0.1 0.2)
      reg_l1_values=(0.001 0.0025 0.0075)
      ;;
    336)
      base_dm=96; base_ff=96; base_el=2; base_lr=0.003; base_wv=db1
      base_alpha=0.9; base_m=1; base_gd=0.5; base_as=1.0
      base_alr=1.0; base_ad=0.0; base_l1=0.0; base_wd=0.01
      arch_profiles=('64 96 2' '64 128 2' '64 128 3' '80 80 2' '96 128 2' '128 128 1')
      lr_values=(0.0024 0.0027 0.0033 0.0036)
      alpha_values=(0.75 0.85 0.95 1.0)
      scale_values=(0.15 0.35 0.6 0.85)
      alr_values=(0.3 0.7)
      fusion_profiles=('96 128 2' '128 128 1')
      fusion_lrs=(0.0027 0.0033)
      fusion_alphas=(0.85 0.95)
      fusion_scales=(0.25 0.6)
      fusion_gd=0.35; fusion_alr=0.5; fusion_ad=0.05; fusion_l1=0.00005; fusion_wd=0.005
      reg_ad_values=(0.05 0.1 0.2)
      reg_l1_values=(0.00001 0.00005 0.0001)
      ;;
    720)
      base_dm=96; base_ff=96; base_el=1; base_lr=0.003; base_wv=db1
      base_alpha=1.0; base_m=1; base_gd=0.5; base_as=1.0
      base_alr=1.0; base_ad=0.0; base_l1=0.00005; base_wd=0.01
      arch_profiles=('64 96 1' '64 128 1' '64 128 2' '80 80 1' '96 128 1' '128 128 1')
      lr_values=(0.0024 0.0027 0.0033 0.0036)
      alpha_values=(0.85 0.9 0.95 1.0)
      scale_values=(0.1 0.25 0.4 0.65)
      alr_values=(0.3 0.7)
      fusion_profiles=('64 128 2' '96 128 1')
      fusion_lrs=(0.0027 0.0033)
      fusion_alphas=(0.9 0.95)
      fusion_scales=(0.2 0.4)
      fusion_gd=0.35; fusion_alr=0.5; fusion_ad=0.05; fusion_l1=0.00001; fusion_wd=0.005
      reg_ad_values=(0.05 0.1 0.2)
      reg_l1_values=(0.0 0.00001 0.0001)
      ;;
  esac
}

for pred_len in 96 192 336 720; do
  set_anchor "$pred_len"

  # Architecture and optimizer interactions.
  for profile in "${arch_profiles[@]}"; do
    read -r dm ff el <<< "$profile"
    for lr in "${lr_values[@]}"; do
      add_candidate "$pred_len" "$dm" "$ff" "$el" "$lr" "$base_wv" \
        "$base_alpha" "$base_m" "$base_gd" "$base_as" "$base_alr" \
        "$base_ad" 24 h 1 "$base_l1" "$base_wd" archlr
    done
  done

  # Joint search of geometric mixing and embedding strength.
  for alpha in "${alpha_values[@]}"; do
    for armor_scale in "${scale_values[@]}"; do
      for armor_lr_scale in "${alr_values[@]}"; do
        add_candidate "$pred_len" "$base_dm" "$base_ff" "$base_el" "$base_lr" \
          "$base_wv" "$alpha" "$base_m" "$base_gd" "$armor_scale" \
          "$armor_lr_scale" "$base_ad" 24 h 1 "$base_l1" "$base_wd" geoarmor
      done
    done
  done

  # Multiscale interactions. m <= 3 avoids invalid circular padding for long filters.
  for wavelet in db1 bior3.1 bior3.3 sym2; do
    for levels in 1 2 3; do
      for geom_dropout in 0.2 0.35; do
        add_candidate "$pred_len" "$base_dm" "$base_ff" "$base_el" "$base_lr" \
          "$wavelet" "$base_alpha" "$levels" "$geom_dropout" "$base_as" \
          "$base_alr" "$base_ad" 24 h 1 "$base_l1" "$base_wd" multiscale
      done
    done
  done

  # Regularization interactions.
  for armor_dropout in "${reg_ad_values[@]}"; do
    for l1_weight in "${reg_l1_values[@]}"; do
      for weight_decay in 0.0 0.005; do
        add_candidate "$pred_len" "$base_dm" "$base_ff" "$base_el" "$base_lr" \
          "$base_wv" "$base_alpha" "$base_m" "$base_gd" "$base_as" \
          "$base_alr" "$armor_dropout" 24 h 1 "$l1_weight" "$weight_decay" regularization
      done
    done
  done

  # Cross-family combinations around the strongest regions.
  for profile in "${fusion_profiles[@]}"; do
    read -r dm ff el <<< "$profile"
    for lr in "${fusion_lrs[@]}"; do
      for alpha in "${fusion_alphas[@]}"; do
        for armor_scale in "${fusion_scales[@]}"; do
          add_candidate "$pred_len" "$dm" "$ff" "$el" "$lr" "$base_wv" \
            "$alpha" "$base_m" "$fusion_gd" "$armor_scale" "$fusion_alr" \
            "$fusion_ad" 24 h 1 "$fusion_l1" "$fusion_wd" fusion
        done
      done
    done
  done
done

echo "Prepared $candidate_count unseen ETTh2 configurations in $manifest"

run_case() {
  local row=$1
  local run_id pred_len d_model d_ff e_layers learning_rate wavelet alpha levels
  local geom_dropout armor_scale armor_lr_scale armor_dropout armor_cycle run_freq
  local normalization l1_weight weight_decay ignored_mse ignored_mae ignored_status
  IFS=, read -r run_id pred_len d_model d_ff e_layers learning_rate wavelet alpha levels \
    geom_dropout armor_scale armor_lr_scale armor_dropout armor_cycle run_freq \
    normalization l1_weight weight_decay ignored_mse ignored_mae ignored_status <<< "$row"

  local log_file="$log_dir/${run_id}.log"
  local status_file="$log_dir/${run_id}.status"
  if [ -f "$status_file" ] && [ "$(cat "$status_file")" = 0 ] && grep -q '^mse:' "$log_file"; then
    echo "Skip completed: $run_id"
    return
  fi

  echo "GPU $gpu_id: starting $run_id"
  if python -u run.py \
    --is_training 1 \
    --lradj TST \
    --train_epochs 10 \
    --patience 3 \
    --root_path ./dataset/ETT-small/ \
    --data_path ETTh2.csv \
    --model_id "$run_id" \
    --model SimpleTM \
    --data ETTh2 \
    --features M \
    --freq "$run_freq" \
    --seq_len 96 \
    --pred_len "$pred_len" \
    --e_layers "$e_layers" \
    --d_model "$d_model" \
    --d_ff "$d_ff" \
    --learning_rate "$learning_rate" \
    --weight_decay "$weight_decay" \
    --batch_size 256 \
    --num_workers 2 \
    --fix_seed 2025 \
    --use_norm "$normalization" \
    --wv "$wavelet" \
    --m "$levels" \
    --geomattn_dropout "$geom_dropout" \
    --enc_in 7 \
    --dec_in 7 \
    --c_out 7 \
    --des ESimpleTMGridETTh2AppendV2 \
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
  echo "GPU $gpu_id: finished $run_id (status $(cat "$status_file"))"
}

while IFS= read -r row; do
  [ "$row" = "$header" ] && continue
  while [ "$(jobs -pr | wc -l)" -ge "$max_jobs" ]; do
    wait -n || true
  done
  run_case "$row" &
done < "$manifest"
wait

# Append results sequentially so concurrent workers cannot corrupt summary.csv.
while IFS= read -r row; do
  [ "$row" = "$header" ] && continue
  IFS=, read -r run_id pred_len d_model d_ff e_layers learning_rate wavelet alpha levels \
    geom_dropout armor_scale armor_lr_scale armor_dropout armor_cycle run_freq \
    normalization l1_weight weight_decay ignored_mse ignored_mae ignored_status <<< "$row"
  if grep -q "^${run_id}," "$summary"; then
    continue
  fi

  log_file="$log_dir/${run_id}.log"
  status_file="$log_dir/${run_id}.status"
  status=1
  [ -f "$status_file" ] && status=$(cat "$status_file")
  metric_line=$(grep '^mse:' "$log_file" 2>/dev/null | tail -n 1 || true)
  mse=''
  mae=''
  if [ -n "$metric_line" ]; then
    mse=$(echo "$metric_line" | sed -E 's/^mse:([^,]+), mae:.*/\1/')
    mae=$(echo "$metric_line" | sed -E 's/.*mae:([^ ]+).*/\1/')
  fi
  echo "${run_id},${pred_len},${d_model},${d_ff},${e_layers},${learning_rate},${wavelet},${alpha},${levels},${geom_dropout},${armor_scale},${armor_lr_scale},${armor_dropout},${armor_cycle},${run_freq},${l1_weight},${weight_decay},${mse},${mae},${status}" >> "$summary"
done < "$manifest"

echo "ETTh2 append grid complete. Results appended to: $summary"
