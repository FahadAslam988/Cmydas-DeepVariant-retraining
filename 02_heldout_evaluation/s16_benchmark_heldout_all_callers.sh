#!/usr/bin/env bash
# ============================================================================
# STEP 5b — Benchmark on the HELD-OUT test region (leakage-free), hap.py.
#
# Compares, ON THE EXACT SAME held-out region (test.bed ∩ callable.bed):
#   NewRetrainedDV  (sim-truth model, ckpt-37632, called fresh in s15)
#   StockDV         (stock DeepVariant WGS)
#   Gatk / BCF / Freebayes / Varscan
#
# For NewRetrainedDV we apply the SAME per-tool filter + normalization as the
# main benchmark. For every other caller we REUSE the already filtered+normalized
# VCFs from the main benchmark (identical processing) and just restrict hap.py
# to the held-out region with -T. => every caller judged identically, same
# region, genotype-aware. Collates SNP + INDEL Precision/Recall/F1, sorted by F1.
# ============================================================================
set -uo pipefail
BASE="/home/work/Desktop/Fahad/03_Corrected_Work/rerun/09_simulation_truthset"
R="$BASE/RUN_DeepVariant_retraining"
D="$R/STEP5_heldout_test_evaluation"
G="$BASE/RUN_DeepVariant_fair_benchmark_simuG-ART/outputs"
REFDIR="/home/work/Desktop/DeepVariantTraining/ref"
REF="$REFDIR/Reference.fasta"                       # same ref used in main benchmark
GDIR="$G/01_mutated_genome"
MAINBENCH="$G/05_benchmark"                          # reuse existing filtered VCFs
TRUTH="$GDIR/truth.vcf.gz"; CALLABLE="$GDIR/callable.bed"
TESTBED="$R/data_split/test.bed"
CALLS="$D/outputs/calls"
BENCH="$D/outputs/benchmark"
RES="$D/outputs/results"
TESTCALL="$BENCH/test_callable.bed"                 # held-out ∩ callable = eval region
BCFT=/home/work/miniconda3/envs/bcftools-env/bin/bcftools
BEDTOOLS=/home/work/miniconda3/bin/bedtools
HAPIMG="jmcdani20/hap.py:v0.3.12"
UG="$(id -u):$(id -g)"; LOG="$D/run.log"
mkdir -p "$BENCH" "$RES"
log(){ echo "[$(date '+%F %T')] [s16] $*" | tee -a "$LOG"; }

EXPR_STD='(FILTER="PASS" || FILTER=".") && FMT/AD[0:1] > 3 && FMT/AD[0:1] / FMT/DP[0] > 0.02'

log "===== STEP 5b held-out benchmark START ====="

# --- 1) build the held-out evaluation region: test.bed ∩ callable.bed -------
if [ ! -s "$TESTCALL" ]; then
  sort -k1,1 -k2,2n "$TESTBED"   > "$BENCH/_test.sorted.bed"
  sort -k1,1 -k2,2n "$CALLABLE"  > "$BENCH/_callable.sorted.bed"
  "$BEDTOOLS" intersect -a "$BENCH/_test.sorted.bed" -b "$BENCH/_callable.sorted.bed" \
    | sort -k1,1 -k2,2n | "$BEDTOOLS" merge > "$TESTCALL"
  rm -f "$BENCH/_test.sorted.bed" "$BENCH/_callable.sorted.bed"
fi
mb=$(awk '{s+=$3-$2} END{printf "%.1f", s/1e6}' "$TESTCALL")
log "eval region (test ∩ callable) = ${mb} Mb, $(wc -l < "$TESTCALL") intervals"

# --- 2) filter + normalize the NEW retrained model's VCF (same as others) ----
NEWFILT="$BENCH/NewRetrainedDV.filt.vcf.gz"
if [ ! -s "$NEWFILT" ]; then
  raw=$("$BCFT" view -H "$CALLS/NewRetrainedDV_test.vcf.gz" 2>/dev/null | wc -l)
  "$BCFT" view -i "$EXPR_STD" "$CALLS/NewRetrainedDV_test.vcf.gz" 2>>"$LOG" \
    | "$BCFT" norm -f "$REF" -m -any 2>>"$LOG" \
    | "$BCFT" sort -Oz -o "$NEWFILT" 2>>"$LOG"
  "$BCFT" index -t "$NEWFILT" 2>>"$LOG"
  kept=$("$BCFT" view -H "$NEWFILT" 2>/dev/null | wc -l)
  log "NewRetrainedDV: filtered $raw -> $kept records"
fi

# --- 3) map every caller label -> its filtered VCF ---------------------------
declare -A VCF=(
  [NewRetrainedDV]="$NEWFILT"
  [StockDV]="$MAINBENCH/StockDV.filt.vcf.gz"
  [Gatk]="$MAINBENCH/Gatk.filt.vcf.gz"
  [BCF]="$MAINBENCH/BCF.filt.vcf.gz"
  [Freebayes]="$MAINBENCH/Freebayes.filt.vcf.gz"
  [Varscan]="$MAINBENCH/Varscan.filt.vcf.gz"
)
ORDER=(NewRetrainedDV StockDV Gatk BCF Freebayes Varscan)

# --- 4) hap.py each caller vs truth, restricted to the held-out region -------
for c in "${ORDER[@]}"; do
  q="${VCF[$c]}"
  [ -s "$BENCH/${c}.summary.csv" ] && { log "$c hap.py exists, skip"; continue; }
  [ -s "$q" ] || { log "$c: filtered VCF missing ($q), skip"; continue; }
  log "hap.py: $c (held-out region) ..."
  docker run --rm -u "$UG" \
    -v "$D/outputs":/data -v "$REFDIR":/ref -v "$GDIR":/truth -v "$MAINBENCH":/main \
    "$HAPIMG" /opt/hap.py/bin/hap.py \
    /truth/truth.vcf.gz "$( [ "$c" = NewRetrainedDV ] && echo /data/benchmark/NewRetrainedDV.filt.vcf.gz || echo /main/$(basename "$q") )" \
    -r /ref/Reference.fasta \
    -T /data/benchmark/test_callable.bed \
    -o /data/benchmark/${c} \
    --threads 32 2>&1 | tail -3 | tee -a "$LOG" || log "!!! hap.py FAILED for $c (continuing)"
done

# --- 5) collate SNP + INDEL metrics, sorted by F1 ----------------------------
collate(){  # $1=Type(SNP|INDEL)  $2=outfile
  local T="$1" OUT="$2"
  printf "Caller\tType\tTRUTH.TOTAL\tTP\tFN\tFP\tRecall\tPrecision\tF1\n" > "$OUT.tmp"
  for c in "${ORDER[@]}"; do
    local s="$BENCH/${c}.summary.csv"
    [ -s "$s" ] || { printf "%s\t%s\tNA\tNA\tNA\tNA\tNA\tNA\tNA\n" "$c" "$T" >> "$OUT.tmp"; continue; }
    awk -F',' -v C="$c" -v T="$T" '
      NR==1{for(i=1;i<=NF;i++) h[$i]=i; next}
      $(h["Type"])==T && $(h["Filter"])=="PASS"{
        printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n", C,T,
          $(h["TRUTH.TOTAL"]),$(h["TRUTH.TP"]),$(h["TRUTH.FN"]),$(h["QUERY.FP"]),
          $(h["METRIC.Recall"]),$(h["METRIC.Precision"]),$(h["METRIC.F1_Score"]) }' "$s" >> "$OUT.tmp" 2>/dev/null
  done
  # header, then rows sorted by F1 desc (NA sinks to bottom)
  { head -1 "$OUT.tmp"; tail -n +2 "$OUT.tmp" | sort -t$'\t' -k9,9gr; } > "$OUT"
  rm -f "$OUT.tmp"
}
collate SNP   "$RES/heldout_ranking_SNP.tsv"
collate INDEL "$RES/heldout_ranking_INDEL.tsv"

echo "# STEP5b_benchmark_DONE $(date '+%F %T')" >> "$D/params.txt"
log "===== STEP 5b DONE ====="
echo "" | tee -a "$LOG"
echo "################## HELD-OUT TEST RESULTS — SNP (sorted by F1) ##################" | tee -a "$LOG"
column -t -s$'\t' "$RES/heldout_ranking_SNP.tsv" | tee -a "$LOG"
echo "" | tee -a "$LOG"
echo "################## HELD-OUT TEST RESULTS — INDEL (sorted by F1) ################" | tee -a "$LOG"
column -t -s$'\t' "$RES/heldout_ranking_INDEL.tsv" | tee -a "$LOG"
