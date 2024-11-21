#!/usr/bin/env bash
export CUDA_VISIBLE_DEVICES=0,1
NP=2 # ./test_bert_sparse_pretrain_train_valid.sh
export NCCL_ASYNC_ERROR_HANDLING=0
set -e
cd ../..
export WANDB_PROJECT=cellular_automata
CUBLAS_WORKSPACE_CONFIG=:4096:2
CUDA_LAUNCH_BLOCKING=1
TASK_NAME=CA
MODEL_TYPE=decoder
MEMORY_CELL=modeling_amt.language_modeling:AssociativeMemoryCell
RECURRENT_WRAPPER=modeling_amt.language_modeling:AssociativeRecurrentWrapper
BACKBONE_CLS=transformers:GPTNeoXForCausalLM

DATASET_PATH=irodkin/1dCA_r2s20T20

ITERS=30000
TBS=256

MAX_N_SEGMENTSS=(10)
MAX_VAL_SEGMENTSS=(10)
SHIFTS=(1)
LRS=(3e-4)
BSS=(128)

MEMORY_SIZE=1
INPUT_TOKENS=231
D_MEM=1
N_HEADS=1

ACT_TYPE=model
MAX_HOP=2

DIM=128
NUM_LAYERS=4

cd base_models/gptconfigs
python create_config.py --hidden_size $DIM --num_hidden_layers $NUM_LAYERS --num_attention_heads $NUM_LAYERS
cd ../..
MODEL_CFG=~/associative-recurrent-memory-transformer/base_models/gptconfigs/neox_tiny_${NUM_LAYERS}l${NUM_LAYERS}hd${DIM}.json


for N in 6
do


for (( j=0; j<${#MAX_N_SEGMENTSS[@]}; j++ ))
do

MAX_N_SEGMENTS=${MAX_N_SEGMENTSS[j]}
MAX_VAL_SEGMENTS=${MAX_VAL_SEGMENTSS[j]}

INPUT_SIZE=$(($INPUT_TOKENS))
INPUT_SEQ_LEN=$(((INPUT_SIZE)*MAX_N_SEGMENTS))
TGT_LEN=$INPUT_SEQ_LEN
LR_=${LRS[j]}
VAL_SEQ_LEN=$(((INPUT_SIZE)*MAX_VAL_SEGMENTS))
SHIFT=${SHIFTS[j]}

BS=${BSS[j]}
K2=-1
for SEGMENT_ORDERING in regular
do

for SCHEDULER in linear
do

for LR in $LR_
do

# if [[ j -gt 0 ]]
# then
#     PREV_SEQ_LEN=$(((INPUT_SIZE)*${MAX_N_SEGMENTSS[j-1]}))
#     MODEL_CPT=../runs/lm_long/armt/${TASK_NAME}/$MODEL_NAME/lr${LRS[j-1]}_${SCHEDULER}_dmem${D_MEM}_${PREV_SEQ_LEN}-${MAX_N_SEGMENTSS[j-1]}x${INPUT_SIZE}_mem${MEMORY_SIZE}_bs${TBS}_iters${ITERS}_${SEGMENT_ORDERING}_bptt-${K2}_act$ACT_TYPE_shift$SHIFT/run_$N 
# else
#     MODEL_CPT=None
# fi
MODEL_CPT=None

echo RUNNING: TASK_NAME SRC_LEN MODEL_NAME MODEL_CLS N_SEG MEMORY_SIZE INPUT_SEQ_LEN LR N
echo RUNNING: $TASK_NAME $SRC_LEN $MODEL_NAME $BACKBONE_CLS $MAX_N_SEGMENTS $MEMORY_SIZE $INPUT_SEQ_LEN $LR $N
accelerate launch --num_processes $NP --config_file  ./accelerate.yaml --main_process_port 29501 run_finetuning_cell_autom.py \
        --task_name $TASK_NAME \
        --model_path ../runs/lm_long/armt/${TASK_NAME}/$MODEL_NAME/lr${LR}_${SCHEDULER}_dmem${D_MEM}_${INPUT_SEQ_LEN}-${MAX_N_SEGMENTS}x${INPUT_SIZE}_mem${MEMORY_SIZE}_bs${TBS}_iters${ITERS}_${SEGMENT_ORDERING}_bptt-${K2}_act$ACT_TYPE_shift$SHIFT/run_$N \
        --model_cfg $MODEL_CFG \
        --dataset_path $DATASET_PATH \
        --model_type $MODEL_TYPE \
        --memory_cell_cls $MEMORY_CELL \
        --recurrent_wrapper_cls $RECURRENT_WRAPPER \
        --model_cls $BACKBONE_CLS \
        --model_cpt $MODEL_CPT \
        --segment_size $INPUT_TOKENS \
        --input_size $INPUT_SIZE \
        --max_n_segments $MAX_N_SEGMENTS \
        --num_mem_tokens $MEMORY_SIZE \
        --num_timesteps $MAX_N_SEGMENTS \
        --num_test_timesteps $MAX_VAL_SEGMENTS \
        --prediction_shift $SHIFT \
        --optimize_metric exact_match --optimize_mode max \
        --batch_size $BS \
        --gradient_accumulation_steps $(($TBS/$BS/$NP)) \
        --iters $ITERS \
        --num_training_steps $(($ITERS*2))\
        --optimizer AdamW  --weight_decay 0.01 \
        --lr ${LR} --lr_scheduler $SCHEDULER --num_warmup_steps 1000 \
        --data_n_workers 2 \
        --log_interval 50 --valid_interval 250 \
        --show_valid_examples 5 \
        --early_stopping_patience 30 \
        --seed $(($N+42*$j)) \
        --clip_grad_value 0.1 \
        --save_best \
        --d_mem $D_MEM \
        --layers_attr gpt_neox.layers \
        --act_on \
        --max_hop $MAX_HOP \
        --time_penalty 3e-4 \
        --act_type $ACT_TYPE \
        --repeat_state
        # --freeze_mem
        # --repeat_state
done
done
done
done
done
echo "done"
