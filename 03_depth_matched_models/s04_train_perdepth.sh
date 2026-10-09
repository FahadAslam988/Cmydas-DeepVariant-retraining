#!/usr/bin/env bash
# ============================================================================
# STEP 4 - Train ONE DeepVariant model per depth, SEQUENTIALLY (GPU).
# Usage: bash s04_train_perdepth.sh          # trains 10x, 15x, 30x
#        bash s04_train_perdepth.sh 30       # or an explicit list
# ----------------------------------------------------------------------------
# CONFIG: copied EXACTLY from the proven 70x run (RUN_DeepVariant_retraining/
#   scripts/s14_train.sh) - dv_config.py:base, warm-start WGS ckpt, batch 128
#   (same as the 70x model), lr 1e-4, 10 epochs, --strategy=mirrored, DV 1.9.0-gpu.
#
# ONE DELIBERATE DIFFERENCE FROM s14:
#   s14 hardcoded --config.num_validation_examples=246807 (the 70x count).
#   Every depth has its OWN validation count:
#       10x=241453   15x=247892   30x=246613   70x=246807
#   Using the wrong number scores checkpoint selection on the wrong data, so
#   this script READS the count from each depth's validation config at runtime.
#
# 70x IS NOT RETRAINED: that model already exists (RUN_DeepVariant_retraining,
#   trained Jul 17) and scored best-of-7 at 70x (SNP F1 0.998114). Retraining it
#   would only reproduce an existing result.
#
# SAFETY: strictly one depth at a time on the single GPU; verifies checkpoints
#   were actually written before moving on; stops the chain on first failure.
# ============================================================================
set -uo pipefail

NEW="/home/work/Desktop/Fahad/03_Corrected_Work/rerun/09_simulation_truthset/RUN_DeepVariant_coverage_augmented_retraining_mixed_10-15-30-70x"
SHUF="$NEW/03_shuffled_examples_per_depth"
MODELS="$NEW/04_trained_models_per_depth"
DVCONFIG="/home/work/Desktop/DeepVariantTraining/Training/dv_config.py"
IMG="google/deepvariant:1.9.0-gpu"
WARM="gs://deepvariant/models/DeepVariant/1.9.0/checkpoints/wgs/deepvariant.wgs.ckpt"
BATCH=128; LR=0.0001; EPOCHS=10
CHAIN="$NEW/s04_chain.out"; LOG="$NEW/run.log"

DEPTHS=("$@"); [ ${#DEPTHS[@]} -eq 0 ] && DEPTHS=(10 15 30)

log(){ echo "[$(date '+%F %T')] [s04] $*" | tee -a "$CHAIN" >> "$LOG"; }

log "===== STEP 4 TRAINING CHAIN START: depths ${DEPTHS[*]} (ONE AT A TIME on the GPU) ====="
[ -s "$DVCONFIG" ] || { log "FATAL: dv_config.py not found at $DVCONFIG"; exit 2; }

for d in "${DEPTHS[@]}"; do
  TRAIN_CFG="$SHUF/${d}x/training/training_set.dataset_config.pbtxt"
  VAL_CFG="$SHUF/${d}x/validation/validation_set.dataset_config.pbtxt"
  OUT="$MODELS/model_${d}x_batch${BATCH}_lr1e-4_${EPOCHS}ep"

  [ -s "$TRAIN_CFG" ] && [ -s "$VAL_CFG" ] || { log "FATAL: ${d}x configs missing - run s03c first"; exit 2; }

  # already trained? (checkpoints present) -> skip, so the chain is resumable
  if [ -d "$OUT/checkpoints" ] && [ "$(ls "$OUT/checkpoints"/ema/*.index 2>/dev/null | wc -l)" -gt 0 ]; then
    log "${d}x already trained ($OUT), SKIP"; continue
  fi

  # THE FIX: read this depth's own validation example count
  NVAL=$(grep -m1 '^num_examples:' "$VAL_CFG" | awk '{print $2}')
  NTRAIN=$(grep -m1 '^num_examples:' "$TRAIN_CFG" | awk '{print $2}')
  [ -n "$NVAL" ] || { log "FATAL: could not read num_examples from $VAL_CFG"; exit 2; }

  mkdir -p "$OUT"
  log ">>> TRAIN ${d}x  train_examples=$NTRAIN  num_validation_examples=$NVAL  batch=$BATCH lr=$LR epochs=$EPOCHS"
  log "    out=$OUT"
  t0=$(date +%s)

  docker run --gpus all --rm -v /home/work:/home/work -w /home/work "$IMG" train \
    --config="${DVCONFIG}:base" \
    --config.train_dataset_pbtxt="$TRAIN_CFG" \
    --config.tune_dataset_pbtxt="$VAL_CFG" \
    --config.num_validation_examples="$NVAL" \
    --config.init_checkpoint="$WARM" \
    --config.num_epochs="$EPOCHS" \
    --config.learning_rate="$LR" \
    --config.batch_size="$BATCH" \
    --experiment_dir="$OUT" \
    --strategy=mirrored >> "$NEW/s04_${d}x.out" 2>&1
  rc=$?
  t1=$(date +%s)
  log "<<< ${d}x finished rc=$rc in $(( (t1-t0)/60 )) min"

  NCK=$(ls "$OUT"/checkpoints/ema/*.index 2>/dev/null | wc -l)
  if [ "$rc" -ne 0 ] || [ "$NCK" -eq 0 ]; then
    log "FAIL: ${d}x rc=$rc, checkpoints written=$NCK. CHAIN STOPPED (no cascade)."
    log "      check: tail -60 $NEW/s04_${d}x.out"
    exit 1
  fi

  BEST=$(ls "$OUT"/checkpoints/ema/*.index 2>/dev/null | sed 's/\.index$//' \
         | awk -F- '{print $(NF-1)" "$0}' | sort -rn | head -1 | cut -d' ' -f2-)
  log "OK ${d}x -> $NCK checkpoints; best-by-val-acc: $(basename "$BEST")"
  echo "$BEST" > "$NEW/05_best_checkpoint_per_depth/best_checkpoint_${d}x.txt"
  echo "# STEP4_train_${d}x_DONE $(date '+%F %T')  train_ex=$NTRAIN val_ex=$NVAL ckpts=$NCK best=$(basename "$BEST")" >> "$NEW/params.txt"
  sleep 15
done

log "===== STEP 4 TRAINING CHAIN DONE ====="
echo "OK $(date '+%F %T')" > "$NEW/STEP4_ALL_TRAINING_DONE.marker"
