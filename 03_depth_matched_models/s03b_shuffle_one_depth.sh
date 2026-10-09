#!/usr/bin/env bash
# ============================================================================
# STEP 3b - Shuffle ONE depth alone (memory-safe per-depth approach)
# Usage: bash s03b_shuffle_one_depth.sh <DEPTH>     e.g. 30
# ----------------------------------------------------------------------------
# WHY per-depth: the single global shuffle of all 4 depths overflowed RAM+swap.
# Each depth alone is SMALLER than the proven 70x run, so it fits safely.
# EXACT proven settings from the 70x run (s13): DirectRunner,
# --direct_num_workers=0. Writes a per-depth DONE marker. Detach-friendly.
# ============================================================================
set -uo pipefail
D="${1:?give a depth, e.g. 30}"
NEW="/home/work/Desktop/Fahad/03_Corrected_Work/rerun/09_simulation_truthset/RUN_DeepVariant_coverage_augmented_retraining_mixed_10-15-30-70x"
SHUF="/home/work/deepvariant-training/tools/shuffle_tfrecords_beam.py"
EX="$NEW/examples/${D}x"
OUTDIR="$NEW/shuffled_perdepth/${D}x"
NSHARDS=15; LOG="$NEW/run.log"
mkdir -p "$OUTDIR/training" "$OUTDIR/validation"
log(){ echo "[$(date '+%F %T')] [s03b ${D}x] $*" | tee -a "$LOG"; }
source /home/work/beam310/bin/activate 2>/dev/null || source /home/work/deepvariant-training/beam/bin/activate

shuffle(){  # $1=set  $2=prefix  $3=dataset_name
  local set="$1" prefix="$2" name="$3"
  [ -s "$OUTDIR/$set/$prefix.dataset_config.pbtxt" ] && { log "$set already shuffled, skip"; return 0; }
  log "shuffling ${D}x $set ..."
  python3 "$SHUF" \
    --input_pattern_list="$EX/${set}/${prefix}.with_label.tfrecord-?????-of-000${NSHARDS}.gz" \
    --output_pattern_prefix="$OUTDIR/$set/$prefix.with_label.shuffled" \
    --output_dataset_name="$name" \
    --output_dataset_config_pbtxt="$OUTDIR/$set/$prefix.dataset_config.pbtxt" \
    --runner=DirectRunner --direct_num_workers=0 2>>"$LOG"
  log "${D}x $set -> $(ls "$OUTDIR/$set/$prefix.with_label.shuffled"* 2>/dev/null | wc -l) shard(s)"
}

log "===== shuffle ${D}x START ====="
shuffle training   training_set   "CheloniaMydas_${D}x_Training"
shuffle validation validation_set "CheloniaMydas_${D}x_Validation"
echo "OK $(date '+%F %T')" > "$NEW/SHUFFLE_${D}x_DONE.marker"
log "===== shuffle ${D}x DONE ====="
