#!/usr/bin/env bash
# ============================================================================
# STEP 3 (retraining) — shuffle the training + validation tfrecords (Apache Beam
# DirectRunner), using the proven shuffle tool + beam venv. Produces the
# shuffled examples + dataset_config.pbtxt that the train step consumes.
# ============================================================================
set -uo pipefail
R="/home/work/Desktop/Fahad/03_Corrected_Work/rerun/09_simulation_truthset/RUN_DeepVariant_retraining"
SHUF="/home/work/deepvariant-training/tools/shuffle_tfrecords_beam.py"
NSHARDS=15; LOG="$R/run.log"
mkdir -p "$R/shuffled/training" "$R/shuffled/validation"
log(){ echo "[$(date '+%F %T')] [s13] $*" | tee -a "$LOG"; }
# activate beam env (proven)
source /home/work/beam310/bin/activate 2>/dev/null || source /home/work/deepvariant-training/beam/bin/activate

shuffle(){  # $1=examples_dir  $2=prefix  $3=outdir  $4=dataset_name
  [ -s "$3/$2.dataset_config.pbtxt" ] && { log "$2 shuffled exists, skip"; return 0; }
  log "shuffling $2 ..."
  python3 "$SHUF" \
    --input_pattern_list="$1/$2.with_label.tfrecord-?????-of-000${NSHARDS}.gz" \
    --output_pattern_prefix="$3/$2.with_label.shuffled" \
    --output_dataset_name="$4" \
    --output_dataset_config_pbtxt="$3/$2.dataset_config.pbtxt" \
    --runner=DirectRunner --direct_num_workers=0 2>>"$LOG"
  log "$2 -> $(ls "$3/$2.with_label.shuffled"* 2>/dev/null | wc -l) file(s); config: $3/$2.dataset_config.pbtxt"
}

log "===== STEP 3 shuffle START ====="
shuffle "$R/examples/training"   training_set   "$R/shuffled/training"   CheloniaMydas_Sim_Training
shuffle "$R/examples/validation" validation_set "$R/shuffled/validation" CheloniaMydas_Sim_Validation
echo "# STEP3_shuffle_DONE $(date '+%F %T')" >> "$R/params.txt" 2>/dev/null || true
log "===== STEP 3 DONE ====="
echo "=== dataset configs ==="; cat "$R/shuffled/training/training_set.dataset_config.pbtxt" 2>/dev/null | head