#!/usr/bin/env bash
# ============================================================================
# STEP 6 - Evaluate each new depth-matched model on the HELD-OUT test regions.
# Usage: bash s05_eval_all_depths.sh          # 10x, 15x, 30x
#        bash s05_eval_all_depths.sh 30       # or an explicit list
# ----------------------------------------------------------------------------
# EVERY STEP MIRRORS THE FROZEN BASELINE EXACTLY. Verified 2026-07-27 against
# RUN_DeepVariant_retraining/STEP5_heldout_test_evaluation/scripts/s15+s16.
# If any of these diverge, the new numbers are NOT comparable to the baseline:
#
#   calling (s15):  --model_type=WGS  --ref=subset.fa  --regions=test.bed
#                   --customized_model=<model>/checkpoints/ema/<best ckpt>
#   VCF filter(s16): bcftools view -i '(FILTER="PASS"||FILTER=".") &&
#                      FMT/AD[0:1]>3 && FMT/AD[0:1]/FMT/DP[0]>0.02'
#                    | bcftools norm -f Reference.fasta -m -any | bcftools sort
#   hap.py  (s16):  jmcdani20/hap.py:v0.3.12
#                   -r Reference.fasta          <- the FULL ref, not subset.fa
#                   -T test_callable.bed        <- test.bed n callable.bed (52.0 Mb)
#                   --threads N                 <- no --engine, no --pass-only
#
# NOTE the two different references, which is deliberate and matches the baseline:
#   subset.fa (72 contigs, 211.7 Mb) for CALLING; Reference.fasta (2.0 G) for
#   normalisation + hap.py.
#
# The evaluation BED is REUSED byte-for-byte from the baseline run so the region
# is provably identical. Test BAMs are the same titration BAMs the baseline used.
# 70x is NOT re-run: its numbers are already frozen in
# 00_baseline_results_BEFORE_new_training/.
#
# SAFETY: one depth at a time; verifies VCF and hap.py summary exist before
# continuing; stops the chain on first failure; resumable.
# ============================================================================
set -uo pipefail

BASE="/home/work/Desktop/Fahad/03_Corrected_Work/rerun/09_simulation_truthset"
NEW="$BASE/RUN_DeepVariant_coverage_augmented_retraining_mixed_10-15-30-70x"
TITR="$BASE/RUN_DeepVariant_lowcoverage_titration/outputs"
GDIR="$BASE/RUN_DeepVariant_fair_benchmark_simuG-ART/outputs/01_mutated_genome"
OLDBENCH="$BASE/RUN_DeepVariant_retraining/STEP5_heldout_test_evaluation/outputs/benchmark"

REFDIR="/home/work/Desktop/DeepVariantTraining/ref"
REF_FULL="$REFDIR/Reference.fasta"        # for bcftools norm + hap.py
REF_CALL="$GDIR/subset.fa"                # for variant calling
TRUTH="$GDIR/truth.vcf.gz"
TESTBED="$NEW/data_split/test.bed"

MODELS="$NEW/04_trained_models_per_depth"
BESTDIR="$NEW/05_best_checkpoint_per_depth"
CALLS="$NEW/06_variant_calls_heldout_testbed"
HAPPY="$NEW/07_happy_benchmark_vs_truth"
EVALBED="$HAPPY/test_callable.bed"

BCFT=/home/work/miniconda3/envs/bcftools-env/bin/bcftools
BEDTOOLS=/home/work/miniconda3/bin/bedtools
DV_IMG="google/deepvariant:1.9.0-gpu"
HAPPY_IMG="jmcdani20/hap.py:v0.3.12"
EXPR_STD='(FILTER="PASS" || FILTER=".") && FMT/AD[0:1] > 3 && FMT/AD[0:1] / FMT/DP[0] > 0.02'
THREADS=$(nproc); UG="$(id -u):$(id -g)"
CHAIN="$NEW/s05_chain.out"; LOG="$NEW/run.log"

DEPTHS=("$@"); [ ${#DEPTHS[@]} -eq 0 ] && DEPTHS=(10 15 30)
log(){ echo "[$(date '+%F %T')] [s05] $*" | tee -a "$CHAIN" >> "$LOG"; }

mkdir -p "$CALLS" "$HAPPY"
log "===== STEP 6 EVALUATION CHAIN START: depths ${DEPTHS[*]} ====="
for f in "$REF_FULL" "$REF_CALL" "$TRUTH" "$TESTBED"; do
  [ -s "$f" ] || { log "FATAL: missing input $f"; exit 2; }
done

# --- evaluation region: reuse the baseline's, else rebuild it identically ----
if [ ! -s "$EVALBED" ]; then
  if [ -s "$OLDBENCH/test_callable.bed" ]; then
    cp -a "$OLDBENCH/test_callable.bed" "$EVALBED"
    log "eval region: REUSED byte-for-byte from baseline ($OLDBENCH/test_callable.bed)"
  else
    sort -k1,1 -k2,2n "$TESTBED"        > "$HAPPY/_t.bed"
    sort -k1,1 -k2,2n "$GDIR/callable.bed" > "$HAPPY/_c.bed"
    "$BEDTOOLS" intersect -a "$HAPPY/_t.bed" -b "$HAPPY/_c.bed" \
      | sort -k1,1 -k2,2n | "$BEDTOOLS" merge > "$EVALBED"
    rm -f "$HAPPY/_t.bed" "$HAPPY/_c.bed"
    log "eval region: rebuilt as test.bed n callable.bed"
  fi
fi
log "eval region = $(awk '{s+=$3-$2}END{printf "%.1f Mb, %d intervals",s/1e6,NR}' "$EVALBED")"

for d in "${DEPTHS[@]}"; do
  BAM="$TITR/${d}x/sim.${d}x.dedup.bam"
  MODELDIR=$(ls -d "$MODELS"/model_${d}x_* 2>/dev/null | head -1)
  CKPT_FILE="$BESTDIR/best_checkpoint_${d}x.txt"
  RAWVCF="$CALLS/DV_retrained_${d}x_test.vcf.gz"
  FILTVCF="$CALLS/DV_retrained_${d}x_test.filt.vcf.gz"
  OUTPFX="$HAPPY/happy_${d}x"
  SUMMARY="${OUTPFX}.summary.csv"

  [ -s "$BAM" ]       || { log "FATAL: test BAM missing: $BAM"; exit 2; }
  [ -d "$MODELDIR" ]  || { log "FATAL: no trained model for ${d}x"; exit 2; }
  [ -s "$CKPT_FILE" ] || { log "FATAL: no best checkpoint for ${d}x"; exit 2; }
  CKPT=$(basename "$(cat "$CKPT_FILE")")
  [ -s "$SUMMARY" ] && { log "${d}x already evaluated, SKIP"; continue; }

  # ---------- 1. call variants on the held-out regions ----------
  if [ ! -s "$RAWVCF" ]; then
    log ">>> ${d}x CALL  model=$(basename "$MODELDIR")/$CKPT  bam=$(basename "$BAM")"
    t0=$(date +%s)
    docker run --gpus all --rm -v /home/work:/home/work -v "$MODELDIR":/model:ro \
      -w /home/work "$DV_IMG" run_deepvariant \
        --model_type=WGS \
        --customized_model="/model/checkpoints/ema/${CKPT}" \
        --ref="$REF_CALL" --reads="$BAM" --regions="$TESTBED" \
        --output_vcf="$RAWVCF" --num_shards="$THREADS" \
        --intermediate_results_dir="$CALLS/tmp_${d}x" \
      >> "$NEW/s05_${d}x.out" 2>&1
    rc=$?; log "<<< ${d}x call rc=$rc in $(( ($(date +%s)-t0)/60 )) min"
    [ "$rc" -eq 0 ] && [ -s "$RAWVCF" ] || {
      log "FAIL: ${d}x calling produced no VCF. CHAIN STOPPED."
      log "      check: tail -60 $NEW/s05_${d}x.out"; exit 1; }
    rm -rf "$CALLS/tmp_${d}x"
  else
    log "${d}x raw VCF exists, reusing"
  fi

  # ---------- 2. filter + normalise (identical to the baseline) ----------
  if [ ! -s "$FILTVCF" ]; then
    raw=$("$BCFT" view -H "$RAWVCF" 2>/dev/null | wc -l)
    "$BCFT" view -i "$EXPR_STD" "$RAWVCF" 2>>"$LOG" \
      | "$BCFT" norm -f "$REF_FULL" -m -any 2>>"$LOG" \
      | "$BCFT" sort -Oz -o "$FILTVCF" 2>>"$LOG"
    "$BCFT" index -t "$FILTVCF" 2>>"$LOG"
    kept=$("$BCFT" view -H "$FILTVCF" 2>/dev/null | wc -l)
    log "${d}x filter+norm: $raw -> $kept records"
    [ -s "$FILTVCF" ] || { log "FAIL: ${d}x filtering produced no VCF. CHAIN STOPPED."; exit 1; }
  fi

  # ---------- 3. hap.py vs truth on the held-out region ----------
  log ">>> ${d}x HAP.PY vs truth"
  t0=$(date +%s)
  docker run --rm -u "$UG" -v /home/work:/home/work -w /home/work "$HAPPY_IMG" \
    /opt/hap.py/bin/hap.py "$TRUTH" "$FILTVCF" \
      -r "$REF_FULL" -T "$EVALBED" -o "$OUTPFX" --threads "$THREADS" \
    >> "$NEW/s05_${d}x.out" 2>&1
  rc=$?; log "<<< ${d}x hap.py rc=$rc in $(( ($(date +%s)-t0)/60 )) min"
  [ "$rc" -eq 0 ] && [ -s "$SUMMARY" ] || {
    log "FAIL: ${d}x hap.py produced no summary. CHAIN STOPPED."
    log "      check: tail -60 $NEW/s05_${d}x.out"; exit 1; }

  # ---------- 4. tidy per-depth TSV ----------
  python3 - "$SUMMARY" "$d" "$HAPPY/results_${d}x.tsv" <<'PY'
import csv, sys
summary, depth, out = sys.argv[1], sys.argv[2], sys.argv[3]
with open(out, "w") as o:
    o.write("Depth\tCaller\tType\tTRUTH.TOTAL\tTP\tFN\tFP\tRecall\tPrecision\tF1\n")
    for r in csv.DictReader(open(summary)):
        if r.get("Filter") != "PASS":
            continue
        o.write("\t".join([f"{depth}x", f"DV_retrained_{depth}x_simTruth", r["Type"],
                           r["TRUTH.TOTAL"], r["TRUTH.TP"], r["TRUTH.FN"], r["QUERY.FP"],
                           r["METRIC.Recall"], r["METRIC.Precision"],
                           r["METRIC.F1_Score"]]) + "\n")
PY

  log "OK ${d}x -> $HAPPY/results_${d}x.tsv"
  tail -n +2 "$HAPPY/results_${d}x.tsv" | while read -r l; do log "    $l"; done
  echo "# STEP6_eval_${d}x_DONE $(date '+%F %T')  ckpt=$CKPT bam=$(basename "$BAM")" >> "$NEW/params.txt"
done

{ echo -e "Depth\tCaller\tType\tTRUTH.TOTAL\tTP\tFN\tFP\tRecall\tPrecision\tF1"
  for d in "${DEPTHS[@]}"; do tail -n +2 "$HAPPY/results_${d}x.tsv" 2>/dev/null; done
} > "$HAPPY/results_all_new_models.tsv"

log "===== STEP 6 EVALUATION CHAIN DONE ====="
echo "OK $(date '+%F %T')" > "$NEW/STEP6_ALL_EVAL_DONE.marker"
