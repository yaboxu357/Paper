export CUDA_VISIBLE_DEVICES=0
mkdir -p logs/grid_e_stage1b

summary="logs/grid_e_stage1b/summary.csv"
echo "pred_len,armor_scale,armor_lr_scale,armor_dropout,mse,mae,status" > "$summary"

for pred_len in 96 192 336 720; do
  case "$pred_len" in
    96)
      e_layers=1; d_model=32; d_ff=32; learning_rate=0.02
      wavelet=db1; levels=3; alpha=0.3; l1_weight=0.0005
      ;;
    192)
      e_layers=1; d_model=32; d_ff=32; learning_rate=0.02
      wavelet=db1; levels=3; alpha=1.0; l1_weight=0.00005
      ;;
    336)
      e_layers=4; d_model=64; d_ff=64; learning_rate=0.002
      wavelet=db1; levels=3; alpha=0.0; l1_weight=0.0
      ;;
    720)
      e_layers=1; d_model=32; d_ff=32; learning_rate=0.009
      wavelet=db1; levels=1; alpha=0.9; l1_weight=0.0005
      ;;
  esac

  for armor_scale in 0.75 1.0 1.25; do
    for armor_lr_scale in 0.6 1.0 1.4; do
      for armor_dropout in 0.0 0.1; do
        tag="p${pred_len}_as${armor_scale}_alr${armor_lr_scale}_ad${armor_dropout}"
        log_file="logs/grid_e_stage1b/ETTh1_${tag}.log"
        echo "Running ${tag}; log: ${log_file}"

        python -u run.py \
          --is_training 1 \
          --lradj TST \
          --patience 3 \
          --root_path ./dataset/ETT-small/ \
          --data_path ETTh1.csv \
          --model_id "ETTh1_EGrid1b_${tag}" \
          --model SimpleTM \
          --data ETTh1 \
          --features M \
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
          --enc_in 7 \
          --dec_in 7 \
          --c_out 7 \
          --des EGrid1b \
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
