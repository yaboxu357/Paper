export CUDA_VISIBLE_DEVICES=0
mkdir -p logs/grid_e_stage1

summary="logs/grid_e_stage1/summary.csv"
echo "armor_scale,armor_lr_scale,armor_dropout,mse,mae,status" > "$summary"

for armor_scale in 0.25 0.5 1.0; do
  for armor_lr_scale in 0.1 0.3; do
    for armor_dropout in 0.0 0.1; do
      tag="as${armor_scale}_alr${armor_lr_scale}_ad${armor_dropout}"
      log_file="logs/grid_e_stage1/ETTh1_96_${tag}.log"
      echo "Running ${tag}; log: ${log_file}"

      python -u run.py \
        --is_training 1 \
        --lradj TST \
        --patience 3 \
        --root_path ./dataset/ETT-small/ \
        --data_path ETTh1.csv \
        --model_id "ETTh1_EGrid_${tag}" \
        --model SimpleTM \
        --data ETTh1 \
        --features M \
        --seq_len 96 \
        --pred_len 96 \
        --e_layers 1 \
        --d_model 32 \
        --d_ff 32 \
        --learning_rate 0.02 \
        --weight_decay 0.01 \
        --batch_size 256 \
        --fix_seed 2025 \
        --use_norm 1 \
        --wv db1 \
        --m 3 \
        --enc_in 7 \
        --dec_in 7 \
        --c_out 7 \
        --des EGrid \
        --itr 1 \
        --alpha 0.3 \
        --l1_weight 0.0005 \
        --use_embedding_armor 1 \
        --armor_cycle 24 \
        --armor_scale "$armor_scale" \
        --armor_lr_scale "$armor_lr_scale" \
        --armor_dropout "$armor_dropout" \
        > "$log_file" 2>&1

      status=$?
      metrics=$(sed -n 's/^mse:\([^,]*\), mae:\(.*\)$/\1,\2/p' "$log_file" | tail -n 1)
      if [ -n "$metrics" ]; then
        echo "${armor_scale},${armor_lr_scale},${armor_dropout},${metrics},${status}" >> "$summary"
      else
        echo "${armor_scale},${armor_lr_scale},${armor_dropout},,,${status}" >> "$summary"
      fi
      echo "Finished ${tag}"
    done
  done
done

echo "Grid complete; summary: ${summary}"
