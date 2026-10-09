#!/usr/bin/env bash
# ============================================================================
# STEP 2 (retraining) — make_examples (TRAINING mode) for the simulation-truth
# retraining. Adapts the proven DV 1.9.0 commands: same channels, same
# --mode training + --truth_variants + --confident_regions; inputs = simulation
# BAM + EXACT simulation truth; regions = leakage-free split (BED files).
# Produces labeled tfrecord examples for TRAIN and VALIDATION sets.
# ============================================================================
set -uo pipefail
BASE="/home/work/Desktop/Fahad/03_Corrected_Work/rerun/09_simulation_truthset"
R="$BASE/RUN_DeepVariant_retraining"
GDIR="$BASE/RUN_DeepVariant_fair_benchmark_simuG-ART/outputs"
# use subset.fa (72 contigs) as ref: matches reads+truth 100% (full Reference.fasta -> DeepVariant
# rejects <10% common-bases safety check). subset.fa has identical contigs/coords to the alignment.
REF="$GDIR/01_mutated_genome/subset.fa"
BAM="$GDIR/03_aligned/sim.dedup.bam"
TRUTH="$GDIR/01_mutated_genome/truth.vcf.gz"
IMG="google/deepvariant:latest"                 # v1.9.0 CPU (make_examples)
NSHARDS=15
CHANNELS="BASE_CHANNELS,insert_size"            # 7 channels — same as 70x run
UG="$(id -u):$(id -g)"; LOG="$R/run.log"
mkdir -p "$R/examples/training" "$R/examples/validation"
log(){ echo "[$(date '+%F %T')] [s12] $*" | tee -a "$LOG"; }

make_ex(){  # $1=regions.bed  $2=outdir  $3=prefix
  local bed="$1" outdir="$2" prefix="$3"
  [ -s "$outdir/${prefix}.with_label.tfrecord-00000-of-000${NSHARDS}.gz" ] && { log "$prefix examples exist, skip"; return 0; }
  seq 0 $((NSHARDS-1)) | xargs -P "$NSHARDS" -I{} \
    docker run --rm --user "$UG" -v /home/work:/home/work "$IMG" \
      /opt/deepvariant/bin/make_examples --mode training \
      --ref "$REF" --reads "$BAM" \
      --examples "$outdir/${prefix}.with_label.tfrecord@${NSHARDS}.gz" \
      --truth_variants "$TRUTH" \
      --confident_regions "$bed" --regions "$bed" \
      --channel_list "$CHANNELS" --task {} 2>>"$LOG"
  local n; n=$(ls "$outdir/${prefix}.with_label.tfrecord-"*.gz 2>/dev/null | wc -l)
  log "$prefix: $n/$NSHARDS shards written"
}

log "===== STEP 2 make_examples (training mode) START ====="
log "reads=$BAM  truth=$TRUTH  channels=$CHANNELS  shards=$NSHARDS"
log "--- TRAIN set (data_split/train.bed) ---"
make_ex "$R/data_split/train.bed" "$R/examples/training"   training_set
log "--- VALIDATION set (data_split/val.bed) ---"
make_ex "$R/data_split/val.bed"   "$R/examples/validation" validation_set
echo "# STEP2_make_examples_DONE $(date '+%F %T')" >> "$R/params.txt" 2>/dev/null || true
log "===== STEP 2 DONE ====="
du -sh "$R/examples/training" "$R/examples/validation" 2>/dev/null | tee -a "$LOG"