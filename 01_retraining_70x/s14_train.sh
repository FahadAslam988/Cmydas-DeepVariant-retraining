#!/usr/bin/env bash
# ============================================================================
# STEP 4 (retraining) — GPU training, EXACTLY the proven DV 1.9.0 command
# (dv_config.py:base, warm-start from WGS ckpt, epochs 10, batch 128, lr 1e-4,
# 7 channels, mirrored). No changes to the config. Inputs = simulation-truth
# shuffled examples + leakage-free split.
# ============================================================================
set -uo pipefail
R="/home/work/Desktop/Fahad/03_Corrected_Work/rerun/09_simulation_truthset/RUN_DeepVariant_retraining"
IMG="google/deepvariant:1.9.0-gpu"; LOG="$R/run.log"
TRAIN_CFG="$R/shuffled/training/training_set.dataset_config.pbtxt"
VAL_CFG="$R/shuffled/validation/validation_set.dataset_config.pbtxt"
MODEL_DIR="$R/model/trained_model"
log(){ echo "[$(date '+%F %T')] [s14] $*" | tee -a "$LOG"; }

[ -s "$TRAIN_CFG" ] && [ -s "$VAL_CFG" ] || { log "ERROR: shuffle dataset configs missing — cannot train"; exit 2; }
mkdir -p "$MODEL_DIR"
log "===== STEP 4 GPU training START (exact config: batch 128, epochs 10, lr 1e-4, warm-start WGS) ====="

DVCONFIG="/home/work/Desktop/DeepVariantTraining/Training/dv_config.py"   # dv_config.py (full path)
# notes from the successful training run: no --config.num_channels (not a field; auto-detected),
# and num_validation_examples must match our val set (246,807) not the 1.5M default.
docker run --gpus all --rm -v /home/work:/home/work -w /home/work "$IMG" train \
  --config="${DVCONFIG}:base" \
  --config.train_dataset_pbtxt="$TRAIN_CFG" \
  --config.tune_dataset_pbtxt="$VAL_CFG" \
  --config.num_validation_examples=246807 \
  --config.init_checkpoint="gs://deepvariant/models/DeepVariant/1.9.0/checkpoints/wgs/deepvariant.wgs.ckpt" \
  --config.num_epochs=10 \
  --config.learning_rate=0.0001 \
  --config.batch_size=128 \
  --experiment_dir="$MODEL_DIR" \
  --strategy=mirrored 2>&1 | tee -a "$LOG"
rc="${PIPESTATUS[0]}"

if [ "$rc" -eq 0 ]; then
  log "===== STEP 4 DONE -> $MODEL_DIR ====="
  echo "# STEP4_train_DONE $(date '+%F %T')" >> "$R/params.txt"
  ls -R "$MODEL_DIR" 2>/dev/null | tail -25 | tee -a "$LOG"
else
  log "ERROR: training exited rc=$rc (see run.log). Fix in the morning."
  exit "$rc"
fi
