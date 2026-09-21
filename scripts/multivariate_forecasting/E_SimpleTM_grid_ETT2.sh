#!/usr/bin/env bash
set -u

dataset_name=${1:?Usage: $0 ETTh1|ETTm1|ETTh2|ETTm2|ECL|Weather|Traffic|Solar|Exchange}
gpu_id=${GPU_ID:-0}
export CUDA_VISIBLE_DEVICES="$gpu_id"
script_dir=$(cd "$(dirname "$0")" && pwd)
cd "$script_dir/../.."

case "$dataset_name" in
  ETTh1)
    root_path=./dataset/ETT-small/
    data_path=ETTh1.csv
    data_name=ETTh1
    channels=7
    frequency=h
    normalization=1
    ;;
  ETTm1)
    root_path=./dataset/ETT-small/
    data_path=ETTm1.csv
    data_name=ETTm1
    channels=7
    frequency=h
    normalization=1
    ;;
  ETTh2)
    root_path=./dataset/ETT-small/
    data_path=ETTh2.csv
    data_name=ETTh2
    channels=7
    frequency=h
    normalization=1
    ;;
  ETTm2)
    root_path=./dataset/ETT-small/
    data_path=ETTm2.csv
    data_name=ETTm2
    channels=7
    frequency=h
    normalization=1
    ;;
  ECL)
    root_path=./dataset/electricity/
    data_path=electricity.csv
    data_name=custom
    channels=321
    frequency=h
    normalization=1
    ;;
  Weather)
    root_path=./dataset/weather/
    data_path=weather.csv
    data_name=custom
    channels=21
    frequency=h
    normalization=1
    ;;
  Traffic)
    root_path=./dataset/traffic/
    data_path=traffic.csv
    data_name=custom
    channels=862
    frequency=h
    normalization=1
    ;;
  Solar)
    root_path=./dataset/solar/
    data_path=solar_AL.txt
    data_name=Solar
    channels=137
    frequency=h
    normalization=0
    ;;
  Exchange)
    if [ -f ./exchange_rate/exchange_rate.csv ]; then
      root_path=./exchange_rate/
    else
      root_path=./dataset/exchange_rate/
    fi
    data_path=exchange_rate.csv
    data_name=custom
    channels=8
    frequency=d
    normalization=1
    ;;
  *)
    echo "Unsupported dataset: $dataset_name" >&2
    exit 2
    ;;
esac

log_dir="logs/esimpletm_grid_expanded_${dataset_name}"
summary="$log_dir/summary.csv"
mkdir -p "$log_dir"
lock_dir="$log_dir/.run_lock"
if ! mkdir "$lock_dir" 2>/dev/null; then
  echo "$dataset_name grid is already running" >&2
  exit 1
fi
trap 'rmdir "$lock_dir" 2>/dev/null || true' EXIT
if [ ! -f "$summary" ]; then
  echo "tag,pred_len,d_model,d_ff,e_layers,learning_rate,wavelet,alpha,m,geomattn_dropout,armor_scale,armor_lr_scale,armor_dropout,armor_cycle,freq,l1_weight,weight_decay,mse,mae,status" > "$summary"
fi

current_weight_decay=0.01

run_one() {
  local tag=$1 pred_len=$2 d_model=$3 d_ff=$4 e_layers=$5 learning_rate=$6
  local wavelet=$7 alpha=$8 levels=$9 geom_dropout=${10} armor_scale=${11}
  local armor_lr_scale=${12} armor_dropout=${13} armor_cycle=${14} run_freq=${15}
  local l1_weight=${16} batch_size=${17}
  local run_id="${dataset_name}_p${pred_len}_${tag}"
  local log_file="$log_dir/${run_id}.log"
  local status_file="$log_dir/${run_id}.status"

  if [ -f "$status_file" ] && [ "$(cat "$status_file")" = 0 ] && grep -q '^mse:' "$log_file"; then
    echo "Skip completed: $run_id"
    return
  fi

  echo "Run: $run_id on physical GPU $gpu_id"
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
    --weight_decay "$current_weight_decay" \
    --batch_size "$batch_size" \
    --fix_seed 2025 \
    --use_norm "$normalization" \
    --wv "$wavelet" \
    --m "$levels" \
    --geomattn_dropout "$geom_dropout" \
    --enc_in "$channels" \
    --dec_in "$channels" \
    --c_out "$channels" \
    --des ESimpleTMGridETT2 \
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
  if ! grep -q "^${run_id}," "$summary"; then
    echo "${run_id},${pred_len},${d_model},${d_ff},${e_layers},${learning_rate},${wavelet},${alpha},${levels},${geom_dropout},${armor_scale},${armor_lr_scale},${armor_dropout},${armor_cycle},${run_freq},${l1_weight},${current_weight_decay},${metrics},${status}" >> "$summary"
  fi
}

for pred_len in 96 192 336 720; do
  case "${dataset_name}_${pred_len}" in
    ETTh1_96)  base_dm=64; base_ff=64;  base_el=1; base_lr=0.02;  base_wv=db1;     base_alpha=0.3; base_m=3; base_gd=0.5; base_l1=0.0005;  base_bs=256; base_as=1.25; base_alr=1.4; base_ad=0.0; base_cycle=24; base_freq=h; base_wd=0.01 ;;
    ETTh1_192) base_dm=32; base_ff=32;  base_el=1; base_lr=0.02;  base_wv=bior3.3; base_alpha=1.0; base_m=3; base_gd=0.5; base_l1=0.00005; base_bs=256; base_as=0.75; base_alr=1.4; base_ad=0.0; base_cycle=24; base_freq=h; base_wd=0.01 ;;
    ETTh1_336) base_dm=64; base_ff=128; base_el=3; base_lr=0.002; base_wv=db1;     base_alpha=0.0; base_m=3; base_gd=0.5; base_l1=0.0;     base_bs=256; base_as=1.25; base_alr=1.4; base_ad=0.1; base_cycle=24; base_freq=h; base_wd=0.01 ;;
    ETTh1_720) base_dm=32; base_ff=32;  base_el=1; base_lr=0.009; base_wv=bior3.3; base_alpha=0.9; base_m=1; base_gd=0.5; base_l1=0.0005;  base_bs=256; base_as=1.25; base_alr=1.4; base_ad=0.0; base_cycle=24; base_freq=h; base_wd=0.01 ;;

    ETTm1_96)  base_dm=64; base_ff=128; base_el=3; base_lr=0.02; base_wv=db1; base_alpha=0.1; base_m=3; base_gd=0.5; base_l1=0.005; base_bs=256; base_as=1.0; base_alr=1.0; base_ad=0.0; base_cycle=24; base_freq=h; base_wd=0.01 ;;
    ETTm1_192) base_dm=32; base_ff=64;  base_el=2; base_lr=0.02; base_wv=db1; base_alpha=0.1; base_m=3; base_gd=0.5; base_l1=0.005; base_bs=256; base_as=1.0; base_alr=1.0; base_ad=0.0; base_cycle=24; base_freq=h; base_wd=0.01 ;;
    ETTm1_336) base_dm=32; base_ff=32;  base_el=1; base_lr=0.02; base_wv=db1; base_alpha=0.1; base_m=1; base_gd=0.5; base_l1=0.005; base_bs=256; base_as=2.0; base_alr=1.0; base_ad=0.0; base_cycle=24; base_freq=h; base_wd=0.01 ;;
    ETTm1_720) base_dm=32; base_ff=32;  base_el=1; base_lr=0.02; base_wv=db4; base_alpha=0.1; base_m=3; base_gd=0.5; base_l1=0.005; base_bs=256; base_as=1.0; base_alr=1.0; base_ad=0.0; base_cycle=24; base_freq=h; base_wd=0.01 ;;

    ETTh2_96)  base_dm=32; base_ff=32;  base_el=1; base_lr=0.006;  base_wv=bior3.3; base_alpha=0.1;  base_m=3; base_gd=0.35; base_l1=0.0005;  base_bs=256; base_as=0.75; base_alr=2.0; base_ad=0.2;  base_cycle=24; base_freq=h; base_wd=0.01 ;;
    ETTh2_192) base_dm=32; base_ff=32;  base_el=1; base_lr=0.0069; base_wv=sym2;    base_alpha=0.1;  base_m=3; base_gd=0.35; base_l1=0.005;   base_bs=256; base_as=1.0;  base_alr=1.0; base_ad=0.0;  base_cycle=24; base_freq=h; base_wd=0.01 ;;
    ETTh2_336) base_dm=96; base_ff=96;  base_el=2; base_lr=0.003;  base_wv=sym2;    base_alpha=0.9;  base_m=2; base_gd=0.35; base_l1=0.0;     base_bs=256; base_as=1.0;  base_alr=1.0; base_ad=0.0;  base_cycle=24; base_freq=h; base_wd=0.01 ;;
    ETTh2_720) base_dm=64; base_ff=128; base_el=2; base_lr=0.0033; base_wv=db1;     base_alpha=0.95; base_m=1; base_gd=0.35; base_l1=0.00001; base_bs=256; base_as=0.2;  base_alr=0.5; base_ad=0.05; base_cycle=24; base_freq=h; base_wd=0.005 ;;

    ETTm2_96)  base_dm=32; base_ff=32; base_el=1; base_lr=0.006;  base_wv=bior3.1; base_alpha=0.3; base_m=3; base_gd=0.5;  base_l1=0.0005;  base_bs=256; base_as=1.0; base_alr=1.0; base_ad=0.0; base_cycle=96; base_freq=t; base_wd=0.01 ;;
    ETTm2_192) base_dm=32; base_ff=32; base_el=1; base_lr=0.0042; base_wv=bior3.1; base_alpha=0.0; base_m=1; base_gd=0.5;  base_l1=0.005;   base_bs=256; base_as=1.0; base_alr=1.0; base_ad=0.0; base_cycle=24; base_freq=h; base_wd=0.01 ;;
    ETTm2_336) base_dm=64; base_ff=64; base_el=1; base_lr=0.006;  base_wv=bior3.3; base_alpha=0.6; base_m=1; base_gd=0.75; base_l1=0.00005; base_bs=128; base_as=1.0; base_alr=1.0; base_ad=0.0; base_cycle=24; base_freq=h; base_wd=0.01 ;;
    ETTm2_720) base_dm=96; base_ff=96; base_el=1; base_lr=0.003;  base_wv=db1;     base_alpha=1.0; base_m=3; base_gd=0.5;  base_l1=0.0;     base_bs=256; base_as=1.0; base_alr=1.0; base_ad=0.0; base_cycle=96; base_freq=t; base_wd=0.01 ;;

    ECL_96)  base_dm=256; base_ff=1024; base_el=1; base_lr=0.01;  base_wv=db1; base_alpha=0.0; base_m=3; base_gd=0.5; base_l1=0.0;     base_bs=256; base_as=1.0; base_alr=1.0; base_ad=0.0; base_cycle=168; base_freq=h; base_wd=0.01 ;;
    ECL_192) base_dm=256; base_ff=1024; base_el=1; base_lr=0.006; base_wv=db1; base_alpha=0.0; base_m=3; base_gd=0.5; base_l1=0.0;     base_bs=256; base_as=1.0; base_alr=1.0; base_ad=0.0; base_cycle=168; base_freq=h; base_wd=0.01 ;;
    ECL_336) base_dm=256; base_ff=1024; base_el=1; base_lr=0.006; base_wv=db1; base_alpha=0.0; base_m=3; base_gd=0.5; base_l1=0.00005; base_bs=256; base_as=1.0; base_alr=1.0; base_ad=0.0; base_cycle=168; base_freq=h; base_wd=0.01 ;;
    ECL_720) base_dm=256; base_ff=1024; base_el=1; base_lr=0.006; base_wv=db1; base_alpha=0.0; base_m=3; base_gd=0.5; base_l1=0.00005; base_bs=256; base_as=1.0; base_alr=1.0; base_ad=0.0; base_cycle=168; base_freq=h; base_wd=0.01 ;;

    Weather_96)  base_dm=96; base_ff=96;  base_el=2; base_lr=0.01;  base_wv=db4; base_alpha=0.3; base_m=1; base_gd=0.5; base_l1=0.00005; base_bs=256; base_as=1.0;  base_alr=1.0; base_ad=0.0; base_cycle=24; base_freq=h; base_wd=0.01 ;;
    Weather_192) base_dm=64; base_ff=64;  base_el=1; base_lr=0.009; base_wv=db4; base_alpha=0.3; base_m=1; base_gd=0.5; base_l1=0.0;     base_bs=256; base_as=1.0;  base_alr=1.0; base_ad=0.0; base_cycle=24; base_freq=h; base_wd=0.01 ;;
    Weather_336) base_dm=64; base_ff=128; base_el=1; base_lr=0.009; base_wv=db4; base_alpha=1.0; base_m=3; base_gd=0.5; base_l1=0.00005; base_bs=256; base_as=1.0;  base_alr=1.0; base_ad=0.0; base_cycle=24; base_freq=h; base_wd=0.01 ;;
    Weather_720) base_dm=32; base_ff=32;  base_el=1; base_lr=0.02;  base_wv=db4; base_alpha=0.9; base_m=1; base_gd=0.5; base_l1=0.005;   base_bs=256; base_as=0.25; base_alr=1.0; base_ad=0.0; base_cycle=24; base_freq=h; base_wd=0.01 ;;

    Traffic_96)  base_dm=512;  base_ff=1024; base_el=2; base_lr=0.003;  base_wv=db1; base_alpha=0.1; base_m=3; base_gd=0.5; base_l1=0.0; base_bs=24; base_as=1.0; base_alr=1.0; base_ad=0.0; base_cycle=168; base_freq=h; base_wd=0.01 ;;
    Traffic_192) base_dm=1024; base_ff=2048; base_el=1; base_lr=0.0005; base_wv=db1; base_alpha=0.1; base_m=1; base_gd=0.5; base_l1=0.0; base_bs=32; base_as=1.0; base_alr=1.0; base_ad=0.0; base_cycle=168; base_freq=h; base_wd=0.01 ;;
    Traffic_336) base_dm=1024; base_ff=2048; base_el=1; base_lr=0.0005; base_wv=db1; base_alpha=0.1; base_m=1; base_gd=0.5; base_l1=0.0; base_bs=32; base_as=1.0; base_alr=1.0; base_ad=0.0; base_cycle=168; base_freq=h; base_wd=0.01 ;;
    Traffic_720) base_dm=1024; base_ff=2048; base_el=1; base_lr=0.0005; base_wv=db1; base_alpha=0.1; base_m=1; base_gd=0.5; base_l1=0.0; base_bs=32; base_as=1.0; base_alr=1.0; base_ad=0.0; base_cycle=168; base_freq=h; base_wd=0.01 ;;

    Solar_96)  base_dm=64;  base_ff=128; base_el=1; base_lr=0.006; base_wv=db8;     base_alpha=0.0; base_m=3; base_gd=0.5; base_l1=0.005; base_bs=256; base_as=0.75; base_alr=1.0; base_ad=0.0; base_cycle=24; base_freq=h; base_wd=0.01 ;;
    Solar_192) base_dm=128; base_ff=256; base_el=1; base_lr=0.003; base_wv=db8;     base_alpha=0.0; base_m=1; base_gd=0.5; base_l1=0.005; base_bs=256; base_as=1.0;  base_alr=1.0; base_ad=0.0; base_cycle=1;  base_freq=h; base_wd=0.01 ;;
    Solar_336) base_dm=128; base_ff=512; base_el=1; base_lr=0.003; base_wv=db8;     base_alpha=0.1; base_m=1; base_gd=0.5; base_l1=0.005; base_bs=256; base_as=1.0;  base_alr=1.0; base_ad=0.0; base_cycle=24; base_freq=h; base_wd=0.01 ;;
    Solar_720) base_dm=128; base_ff=256; base_el=1; base_lr=0.009; base_wv=bior3.1; base_alpha=0.0; base_m=1; base_gd=0.5; base_l1=0.005; base_bs=256; base_as=1.0;  base_alr=1.0; base_ad=0.0; base_cycle=24; base_freq=h; base_wd=0.01 ;;

    Exchange_96)  base_dm=384; base_ff=512; base_el=2; base_lr=0.0002; base_wv=db1; base_alpha=0.3; base_m=3; base_gd=0.5; base_l1=0.00005; base_bs=128; base_as=1.0; base_alr=1.0; base_ad=0.0; base_cycle=7; base_freq=d; base_wd=0.01 ;;
    Exchange_192) base_dm=128; base_ff=128; base_el=1; base_lr=0.001;  base_wv=db1; base_alpha=0.3; base_m=3; base_gd=0.5; base_l1=0.00005; base_bs=128; base_as=1.0; base_alr=1.0; base_ad=0.0; base_cycle=7; base_freq=d; base_wd=0.01 ;;
    Exchange_336) base_dm=384; base_ff=512; base_el=2; base_lr=0.01;   base_wv=db1; base_alpha=0.3; base_m=3; base_gd=0.5; base_l1=0.00005; base_bs=128; base_as=1.0; base_alr=1.0; base_ad=0.0; base_cycle=7; base_freq=d; base_wd=0.01 ;;
    Exchange_720) base_dm=256; base_ff=512; base_el=2; base_lr=0.002;  base_wv=db1; base_alpha=0.3; base_m=3; base_gd=0.5; base_l1=0.00005; base_bs=128; base_as=1.0; base_alr=1.0; base_ad=0.0; base_cycle=7; base_freq=d; base_wd=0.01 ;;
  esac

  current_weight_decay=$base_wd

  run_one base "$pred_len" "$base_dm" "$base_ff" "$base_el" "$base_lr" "$base_wv" "$base_alpha" "$base_m" "$base_gd" "$base_as" "$base_alr" "$base_ad" "$base_cycle" "$base_freq" "$base_l1" "$base_bs"

  if [ "$dataset_name" = Traffic ]; then
    architecture_profiles=(
      "256 512 1" "256 1024 1" "512 1024 1" "512 1024 2"
      "512 2048 1" "768 1536 1" "1024 2048 1" "1024 2048 2"
    )
  elif [ "$dataset_name" = ECL ]; then
    architecture_profiles=(
      "64 256 1" "128 256 1" "128 512 1" "128 512 2"
      "192 512 1" "256 512 1" "256 1024 1" "256 1024 2"
      "384 1024 1" "512 1024 1"
    )
  elif [ "$dataset_name" = Solar ]; then
    architecture_profiles=(
      "32 64 1" "64 128 1" "64 256 1" "64 256 2"
      "96 192 1" "128 128 1" "128 256 1" "128 256 2"
      "128 512 1" "256 256 1" "256 512 1" "256 512 2"
    )
  else
    architecture_profiles=(
      "16 16 1" "16 32 1" "32 32 1" "32 64 1" "32 128 1"
      "32 64 2" "64 64 1" "64 128 1" "64 64 2" "64 128 2"
      "64 128 3" "64 256 1" "64 256 2" "96 96 1" "96 192 1"
      "96 96 2" "96 192 2" "128 256 1" "128 256 2"
    )
  fi
  profile_id=0
  for profile in "${architecture_profiles[@]}"; do
    profile_id=$((profile_id + 1))
    read -r dm ff el <<< "$profile"
    if [ "$dm" = "$base_dm" ] && [ "$ff" = "$base_ff" ] && [ "$el" = "$base_el" ]; then
      continue
    fi
    run_one "arch${profile_id}" "$pred_len" "$dm" "$ff" "$el" "$base_lr" "$base_wv" "$base_alpha" "$base_m" "$base_gd" "$base_as" "$base_alr" "$base_ad" "$base_cycle" "$base_freq" "$base_l1" "$base_bs"
  done

  case "$base_lr" in
    0.02)  lr_values=(0.012 0.016 0.024 0.03) ;;
    0.01)  lr_values=(0.006 0.008 0.012 0.015) ;;
    0.009) lr_values=(0.0054 0.0072 0.0108 0.0135) ;;
    0.006) lr_values=(0.0042 0.0051 0.0069 0.0084) ;;
    0.003) lr_values=(0.0021 0.00255 0.00345 0.0042) ;;
    0.002) lr_values=(0.0012 0.0016 0.0024 0.003) ;;
    0.001) lr_values=(0.0006 0.0008 0.0012 0.0015) ;;
    0.0005) lr_values=(0.0003 0.0004 0.0006 0.00075) ;;
    0.0001) lr_values=(0.00005 0.00008 0.00012 0.0002) ;;
  esac
  for value in "${lr_values[@]}"; do
    run_one "lr${value}" "$pred_len" "$base_dm" "$base_ff" "$base_el" "$value" "$base_wv" "$base_alpha" "$base_m" "$base_gd" "$base_as" "$base_alr" "$base_ad" "$base_cycle" "$base_freq" "$base_l1" "$base_bs"
  done

  for value in 0.0 0.1 0.2 0.3 0.45 0.6 0.75 0.9 1.0; do
    [ "$value" = "$base_alpha" ] && continue
    run_one "alpha${value}" "$pred_len" "$base_dm" "$base_ff" "$base_el" "$base_lr" "$base_wv" "$value" "$base_m" "$base_gd" "$base_as" "$base_alr" "$base_ad" "$base_cycle" "$base_freq" "$base_l1" "$base_bs"
  done
  for value in 1 2 3 4 5; do
    [ "$value" = "$base_m" ] && continue
    run_one "m${value}" "$pred_len" "$base_dm" "$base_ff" "$base_el" "$base_lr" "$base_wv" "$base_alpha" "$value" "$base_gd" "$base_as" "$base_alr" "$base_ad" "$base_cycle" "$base_freq" "$base_l1" "$base_bs"
  done
  for value in 0.1 0.25 0.35 0.65 0.75 0.9; do
    run_one "gd${value}" "$pred_len" "$base_dm" "$base_ff" "$base_el" "$base_lr" "$base_wv" "$base_alpha" "$base_m" "$value" "$base_as" "$base_alr" "$base_ad" "$base_cycle" "$base_freq" "$base_l1" "$base_bs"
  done
  for value in 0.25 0.5 0.75 1.0 1.25 1.5 2.0 2.5; do
    [ "$value" = "$base_as" ] && continue
    run_one "as${value}" "$pred_len" "$base_dm" "$base_ff" "$base_el" "$base_lr" "$base_wv" "$base_alpha" "$base_m" "$base_gd" "$value" "$base_alr" "$base_ad" "$base_cycle" "$base_freq" "$base_l1" "$base_bs"
  done
  for value in 0.3 0.5 0.8 1.0 1.4 2.0 3.0; do
    [ "$value" = "$base_alr" ] && continue
    run_one "alr${value}" "$pred_len" "$base_dm" "$base_ff" "$base_el" "$base_lr" "$base_wv" "$base_alpha" "$base_m" "$base_gd" "$base_as" "$value" "$base_ad" "$base_cycle" "$base_freq" "$base_l1" "$base_bs"
  done
  for value in 0.0 0.05 0.1 0.2 0.3 0.4; do
    [ "$value" = "$base_ad" ] && continue
    run_one "ad${value}" "$pred_len" "$base_dm" "$base_ff" "$base_el" "$base_lr" "$base_wv" "$base_alpha" "$base_m" "$base_gd" "$base_as" "$base_alr" "$value" "$base_cycle" "$base_freq" "$base_l1" "$base_bs"
  done

  for value in db1 db2 db4 db8 bior3.1 bior3.3 sym2; do
    [ "$value" = "$base_wv" ] && continue
    run_one "wv${value}" "$pred_len" "$base_dm" "$base_ff" "$base_el" "$base_lr" "$value" "$base_alpha" "$base_m" "$base_gd" "$base_as" "$base_alr" "$base_ad" "$base_cycle" "$base_freq" "$base_l1" "$base_bs"
  done

  for value in 0.0 0.00005 0.0001 0.0005 0.001 0.005; do
    [ "$value" = "$base_l1" ] && continue
    run_one "l1_${value}" "$pred_len" "$base_dm" "$base_ff" "$base_el" "$base_lr" "$base_wv" "$base_alpha" "$base_m" "$base_gd" "$base_as" "$base_alr" "$base_ad" "$base_cycle" "$base_freq" "$value" "$base_bs"
  done

  for value in 0.0 0.001 0.005 0.05; do
    current_weight_decay=$value
    run_one "wd${value}" "$pred_len" "$base_dm" "$base_ff" "$base_el" "$base_lr" "$base_wv" "$base_alpha" "$base_m" "$base_gd" "$base_as" "$base_alr" "$base_ad" "$base_cycle" "$base_freq" "$base_l1" "$base_bs"
  done
  current_weight_decay=$base_wd

  interaction_id=0
  for profile in "${architecture_profiles[0]}" "${architecture_profiles[1]}"; do
    read -r dm ff el <<< "$profile"
    for lr in "${lr_values[0]}" "${lr_values[3]}"; do
      for armor_scale in 0.75 1.25; do
        interaction_id=$((interaction_id + 1))
        run_one "joint${interaction_id}" "$pred_len" "$dm" "$ff" "$el" "$lr" "$base_wv" "$base_alpha" "$base_m" "$base_gd" "$armor_scale" "$base_alr" "$base_ad" "$base_cycle" "$base_freq" "$base_l1" "$base_bs"
      done
    done
  done

  if [ "$dataset_name" = Solar ]; then
    run_one cycle1 "$pred_len" "$base_dm" "$base_ff" "$base_el" "$base_lr" "$base_wv" "$base_alpha" "$base_m" "$base_gd" "$base_as" "$base_alr" "$base_ad" 1 h "$base_l1" "$base_bs"
  elif [ "$dataset_name" = Exchange ]; then
    run_one cycle7 "$pred_len" "$base_dm" "$base_ff" "$base_el" "$base_lr" "$base_wv" "$base_alpha" "$base_m" "$base_gd" "$base_as" "$base_alr" "$base_ad" 7 d "$base_l1" "$base_bs"
  elif [ "$dataset_name" = ETTh1 ] || [ "$dataset_name" = ETTh2 ] || [ "$dataset_name" = ECL ] || [ "$dataset_name" = Weather ] || [ "$dataset_name" = Traffic ]; then
    run_one cycle168 "$pred_len" "$base_dm" "$base_ff" "$base_el" "$base_lr" "$base_wv" "$base_alpha" "$base_m" "$base_gd" "$base_as" "$base_alr" "$base_ad" 168 h "$base_l1" "$base_bs"
  else
    run_one cycle96 "$pred_len" "$base_dm" "$base_ff" "$base_el" "$base_lr" "$base_wv" "$base_alpha" "$base_m" "$base_gd" "$base_as" "$base_alr" "$base_ad" 96 t "$base_l1" "$base_bs"
  fi
done

echo "E-SimpleTM grid complete: $summary"
