export CUDA_VISIBLE_DEVICES=0

log_dir="logs/grid_e_etth2_expanded"
mkdir -p "$log_dir"

summary="$log_dir/summary.csv"
echo "pred_len,armor_scale,armor_lr_scale,armor_dropout,mse,mae,status" > "$summary"

for pred_len in 96 192 336 720; do
  case "$pred_len" in
    96)
      learning_rate=0.006
      wavelet=bior3.1; levels=1; alpha=0.1; l1_weight=0.0005
      ;;
    192)
      learning_rate=0.006
      wavelet=db1; levels=1; alpha=0.1; l1_weight=0.005
      ;;
    336)
      learning_rate=0.003
      wavelet=db1; levels=1; alpha=0.9; l1_weight=0.0
      ;;
    720)
      learning_rate=0.003
      wavelet=db1; levels=1; alpha=1.0; l1_weight=0.00005
      ;;
  esac

  for armor_scale in 0.5 0.75 1.0 1.25 1.5 2.0; do
    for armor_lr_scale in 0.5 0.8 1.0 1.4 2.0; do
      for armor_dropout in 0.0 0.05 0.1 0.2; do
        tag="p${pred_len}_as${armor_scale}_alr${armor_lr_scale}_ad${armor_dropout}"
        log_file="$log_dir/ETTh2_${tag}.log"
        echo "Running ${tag}; log: ${log_file}"

        python -u run.py \
          --is_training 1 \
          --lradj TST \
          --patience 3 \
          --root_path ./dataset/ETT-small/ \
          --data_path ETTh2.csv \
          --model_id "ETTh2_EGridExpanded_${tag}" \
          --model SimpleTM \
          --data ETTh2 \
          --features M \
          --seq_len 96 \
          --pred_len "$pred_len" \
          --e_layers 1 \
          --d_model 32 \
          --d_ff 32 \
          --learning_rate "$learning_rate" \
          --weight_decay 0.01 \
          --batch_size 256 \
          --fix_seed 2025 \
          --use_norm 1 \
          --wv "$wavelet" \
          --m "$levels" \
          --enc_in 7 \
          --dec_in 7 \
          --c_out 7 \
          --des EGridExpanded \
          --itr 1 \
          --alpha "$alpha" \
          --l1_weight "$l1_weight" \
          --use_embedding_armor 1 \
          --armor_cycle 24 \
          --armor_scale "$armor_scale" \
          --armor_lr_scale "$armor_lr_scale" \
          --armor_dropout "$armor_dropout" \
          > "$log_file" 2>&1

        status=$?
        metrics=$(sed -n 's/^mse:\([^,]*\), mae:\(.*\)$/\1,\2/p' "$log_file" | tail -n 1)
        if [ -n "$metrics" ]; then
          echo "${pred_len},${armor_scale},${armor_lr_scale},${armor_dropout},${metrics},${status}" >> "$summary"
        else
          echo "${pred_len},${armor_scale},${armor_lr_scale},${armor_dropout},,,${status}" >> "$summary"
        fi
        echo "Finished ${tag}"
      done
    done
  done
done

echo "Grid complete; summary: ${summary}"
