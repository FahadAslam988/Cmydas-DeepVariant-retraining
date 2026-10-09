#!/usr/bin/env bash
# ============================================================================
# STEP 2 - make_examples (TRAINING mode) at each depth (10x,15x,30x) + reuse 70x
# ----------------------------------------------------------------------------
# WHY: DeepVariant learns from labeled pileup "examples", not raw BAMs. For
# coverage augmentation we build labeled examples at every depth and later mix
# them (STEP 3). Settings are IDENTICAL to the 70x run (s12):
#   --mode training, 7 channels (BASE_CHANNELS,insert_size), subset.fa ref,
#   simulation truth.vcf.gz, leakage-free train.bed/val.bed, 15 shards.
# Refs: Poplin et al. 2018 (Nat Biotechnol); DeepVariant training docs.
# 70x examples already exist (old run) -> reuse via symlink (no recompute).
# Resumable: skips any depth/set whose shards already exist. Logged.
# ============================================================================
set -uo pipefail
B="/home/work/Desktop/Fahad/03_Corrected_Work/rerun/09_simulation_truthset"
NEW="$B/RUN_DeepVariant_coverage_augmented_retraining_mixed_10-15-30-70x"
GDIR="$B/RUN_DeepVariant_fair_benchmark_simuG-ART/outputs"
OLD="$B/RUN_DeepVariant_retraining"
REF="$GDIR/01_mutated_genome/subset.fa"          # 72-contig ref matching reads+truth
TRUTH="$GDIR/01_mutated_genome/truth.vcf.gz"
IMG="google/deepvariant:latest"                  # v1.9.0 CPU
NSHARDS=15
CHANNELS="BASE_CHANNELS,insert_size"             # 7 channels, same as working run
UG="$(id -u):$(id -g)"
LOG="$NEW/run.log"
EX="$NEW/examples"
log(){ echo "[$(date '+%F %T')] [s02] $*" | tee -a "$LOG"; }

make_ex(){  # $1=bam  $2=regions.bed  $3=outdir  $4=prefix
  local bam="$1" bed="$2" outdir="$3" prefix="$4"
  mkdir -p "$outdir"
  local last="$outdir/${prefix}.with_label.tfrecord-000$((NSHARDS-1))-of-000${NSHARDS}.gz"
  if [ -s "$last" ]; then log "$prefix examples exist, skip"; return 0; fi
  seq 0 $((NSHARDS-1)) | xargs -P "$NSHARDS" -I{} \
    docker run --rm --user "$UG" -v /home/work:/home/work "$IMG" \
      /opt/deepvariant/bin/make_examples --mode training \
      --ref "$REF" --reads "$bam" \
      --examples "$outdir/${prefix}.with_label.tfrecord@${NSHARDS}.gz" \
      --truth_variants "$TRUTH" \
      --confident_regions "$bed" --regions "$bed" \
      --channel_list "$CHANNELS" --task {} 2>>"$LOG"
  local n; n=$(ls "$outdir/${prefix}.with_label.tfrecord-"*.gz 2>/dev/null | wc -l)
  log "$prefix: $n/$NSHARDS shards written"
}

log "===== STEP 2 make_examples START (depths 10/15/30x fresh, 70x reused) ====="

# --- 10x, 15x, 30x : generate fresh ---
for d in 10 15 30; do
  BAM="$NEW/downsampled_bams/sim_${d}x.dedup.bam"
  log "--- ${d}x TRAIN ---"; make_ex "$BAM" "$NEW/data_split/train.bed" "$EX/${d}x/training"   training_set
  log "--- ${d}x VAL   ---"; make_ex "$BAM" "$NEW/data_split/val.bed"   "$EX/${d}x/validation" validation_set
done

# --- 70x : reuse the already-made examples from the old retraining run (symlink) ---
log "--- 70x: reusing existing examples from old run (symlink, no recompute) ---"
mkdir -p "$EX/70x/training" "$EX/70x/validation"
ln -sf "$OLD/examples/training/"*.gz   "$EX/70x/training/"   2>>"$LOG"
ln -sf "$OLD/examples/validation/"*.gz "$EX/70x/validation/" 2>>"$LOG"
log "70x train shards linked: $(ls "$EX/70x/training/"*.gz 2>/dev/null | wc -l), val: $(ls "$EX/70x/validation/"*.gz 2>/dev/null | wc -l)"

echo "# STEP2_make_examples_DONE $(date '+%F %T')" >> "$NEW/params.txt"
log "===== STEP 2 DONE ====="
du -sh "$EX"/*/training "$EX"/*/validation 2>/dev/null | tee -a "$LOG"
