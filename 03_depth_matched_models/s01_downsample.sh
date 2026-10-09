#!/usr/bin/env bash
# ============================================================================
# STEP 1 - Downsample the 70x simulated BAM to 30x, 15x, 10x
# ----------------------------------------------------------------------------
# WHY: DeepVariant's released models are trained with reads downsampled to
# multiple coverages so ONE model is robust across depth (coverage augmentation).
# Refs: Poplin et al. 2018 (Nat Biotechnol); DeepVariant training docs/blog;
#       Yun et al. 2020 (down to 15x). Subsampling tool: samtools view -s
#       (Danecek et al. 2021, GigaScience).
# Reproducible: fixed seed 42; resumable: skips any depth already done; logged.
# ============================================================================
set -uo pipefail
NEW="/home/work/Desktop/Fahad/03_Corrected_Work/rerun/09_simulation_truthset/RUN_DeepVariant_coverage_augmented_retraining_mixed_10-15-30-70x"
SRC="/home/work/Desktop/Fahad/03_Corrected_Work/rerun/09_simulation_truthset/RUN_DeepVariant_fair_benchmark_simuG-ART/outputs/03_aligned/sim.dedup.bam"
SAM=/home/work/miniconda3/bin/samtools
OUT="$NEW/downsampled_bams"
TRAINBED="$NEW/data_split/train.bed"
LOG="$NEW/run.log"
SEED=42
THREADS=12
mkdir -p "$OUT"
log(){ echo "[$(date '+%F %T')] [s01] $*" | tee -a "$LOG"; }

# depth -> fraction (from STEP1 measurement, measured mean = 69.71x)
declare -A FRAC=( [30]=0.4304 [15]=0.2152 [10]=0.1435 )

log "===== STEP 1 downsample START (seed=$SEED, src=69.71x) ====="

one_depth(){
  local d="$1" f="${FRAC[$1]}"
  local obam="$OUT/sim_${d}x.dedup.bam"
  if [ -s "$obam" ] && [ -s "$obam.bai" ]; then
    log "${d}x already exists, skip"; return 0
  fi
  log "--- making ${d}x (keep fraction $f) ---"
  "$SAM" view -@ "$THREADS" -b -s "${SEED}.${f#0.}" -o "$obam" "$SRC" 2>>"$LOG"
  "$SAM" index -@ "$THREADS" "$obam" 2>>"$LOG"
  # verify actual delivered depth over train regions
  local got
  got=$("$SAM" bedcov "$TRAINBED" "$obam" 2>/dev/null | awk '{s+=$4;b+=($3-$2)} END{printf "%.2f", s/b}')
  log "${d}x DONE -> measured ${got}x (target ${d}x)  file=$(du -h "$obam" | cut -f1)"
  echo "MEASURED_${d}x=${got}" >> "$NEW/params.txt"
}

for d in 30 15 10; do one_depth "$d"; done

echo "# STEP1_DOWNSAMPLE_DONE $(date '+%F %T')" >> "$NEW/params.txt"
log "===== STEP 1 DONE ====="
log "outputs:"; ls -lh "$OUT"/*.bam 2>/dev/null | awk '{print "  "$9" "$5}' | tee -a "$LOG"
