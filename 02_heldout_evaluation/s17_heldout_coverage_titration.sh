#!/usr/bin/env bash
# ============================================================================
# STEP 5c — Held-out test evaluation ACROSS COVERAGE (70x done; add 30x/15x/10x).
#
# For each downsampled depth we call the NEW simulation-truth model (ckpt-37632)
# on the HELD-OUT test.bed using that depth's BAM, then benchmark every caller
# on the SAME held-out region (test ∩ callable) with hap.py. All non-DV callers
# REUSE the titration run's already
# filtered/normalized per-depth VCFs — so only the new model is called fresh.
# Produces per-depth SNP+INDEL rankings + an accuracy-vs-coverage table that
# includes the 70x point from Step 5b.
# ============================================================================
set -uo pipefail
BASE="/home/work/Desktop/Fahad/03_Corrected_Work/rerun/09_simulation_truthset"
R="$BASE/RUN_DeepVariant_retraining"
D="$R/STEP5_heldout_test_evaluation"
G="$BASE/RUN_DeepVariant_fair_benchmark_simuG-ART/outputs"
T="$BASE/RUN_DeepVariant_lowcoverage_titration/outputs"     # downsampled BAMs + per-depth filtered VCFs
REFDIR="/home/work/Desktop/DeepVariantTraining/ref"; REF="$REFDIR/Reference.fasta"
SUBSET="$G/01_mutated_genome/subset.fa"                     # ref the sim BAMs are aligned to
GDIR="$G/01_mutated_genome"; TRUTH="$GDIR/truth.vcf.gz"
MODELDIR="$R/model/trained_model"; CKPT="checkpoint-37632-0.99967-1"
TESTBED="$R/data_split/test.bed"
TESTCALL="$D/outputs/benchmark/test_callable.bed"           # built in s16 (held-out ∩ callable)
BCFT=/home/work/miniconda3/envs/bcftools-env/bin/bcftools
HAPIMG="jmcdani20/hap.py:v0.3.12"; DVIMG="google/deepvariant:latest"
UG="$(id -u):$(id -g)"; LOG="$D/run.log"
EXPR_STD='(FILTER="PASS" || FILTER=".") && FMT/AD[0:1] > 3 && FMT/AD[0:1] / FMT/DP[0] > 0.02'
log(){ echo "[$(date '+%F %T')] [s17] $*" | tee -a "$LOG"; }

[ -s "$TESTCALL" ] || { log "ERROR: $TESTCALL missing (run s16 first)"; exit 2; }

# map label -> reused titration filtered VCF basename (in $T/<cov>x/benchmark/)
declare -A SRC=( [StockDV]=StockDV_sim [Gatk]=Gatk_sim
                 [BCF]=BCF_sim [Freebayes]=Freebayes_sim [Varscan]=Varscan_sim )
ORDER=(NewRetrainedDV StockDV Gatk BCF Freebayes Varscan)

for cov in 30 15 10; do
  BAM="$T/${cov}x/sim.${cov}x.dedup.bam"
  CDIR="$D/outputs/coverage/${cov}x"; mkdir -p "$CDIR"
  [ -s "$BAM" ] || { log "${cov}x: BAM missing, skip"; continue; }
  log "=================== HELD-OUT @ ${cov}x ==================="

  # --- 1) call NEW model on test.bed with the downsampled BAM ---------------
  NV="$CDIR/NewRetrainedDV_test_${cov}x.vcf.gz"
  if [ ! -s "$NV" ]; then
    log "${cov}x: calling NewRetrainedDV on test.bed ..."
    docker run --rm --user "$UG" \
      -v "$GDIR":/ref:ro -v "$T/${cov}x":/bam:ro -v "$MODELDIR":/model:ro \
      -v "$CDIR":/output -v "$R/data_split":/beds:ro \
      "$DVIMG" /opt/deepvariant/bin/run_deepvariant \
      --model_type=WGS --customized_model=/model/checkpoints/ema/${CKPT} \
      --ref=/ref/subset.fa --reads=/bam/sim.${cov}x.dedup.bam --regions=/beds/test.bed \
      --output_vcf=/output/NewRetrainedDV_test_${cov}x.vcf.gz \
      --output_gvcf=/output/NewRetrainedDV_test_${cov}x.g.vcf.gz \
      --num_shards=80 --intermediate_results_dir=/output/intermediates_${cov}x \
      --make_examples_extra_args="small_model_call_multiallelics=false" \
      2>&1 | tail -8 | tee -a "$LOG"
    rm -rf "$CDIR/intermediates_${cov}x"
  fi
  [ -s "$NV" ] || { log "${cov}x: NewRetrainedDV call FAILED, skip depth"; continue; }

  # --- 2) filter+normalize the new model's VCF -----------------------------
  NF="$CDIR/NewRetrainedDV.filt.vcf.gz"
  if [ ! -s "$NF" ]; then
    "$BCFT" view -i "$EXPR_STD" "$NV" 2>>"$LOG" | "$BCFT" norm -f "$REF" -m -any 2>>"$LOG" \
      | "$BCFT" sort -Oz -o "$NF" 2>>"$LOG"; "$BCFT" index -t "$NF" 2>>"$LOG"
    log "${cov}x: NewRetrainedDV filtered -> $("$BCFT" view -H "$NF" | wc -l) records"
  fi

  # --- 3) hap.py every caller on the held-out region -----------------------
  for c in "${ORDER[@]}"; do
    [ -s "$CDIR/${c}.summary.csv" ] && continue
    if [ "$c" = NewRetrainedDV ]; then QARG="/new/NewRetrainedDV.filt.vcf.gz"
    else QARG="/titr/${cov}x/benchmark/${SRC[$c]}.filt.vcf.gz"
         [ -s "$T/${cov}x/benchmark/${SRC[$c]}.filt.vcf.gz" ] || { log "${cov}x $c: source filt VCF missing, skip"; continue; }
    fi
    log "${cov}x hap.py: $c ..."
    docker run --rm -u "$UG" \
      -v "$GDIR":/truth -v "$REFDIR":/ref -v "$D/outputs/benchmark":/region \
      -v "$CDIR":/new -v "$T":/titr -v "$CDIR":/out \
      "$HAPIMG" /opt/hap.py/bin/hap.py \
      /truth/truth.vcf.gz "$QARG" -r /ref/Reference.fasta \
      -T /region/test_callable.bed -o /out/${c} --threads 32 \
      2>&1 | tail -2 | tee -a "$LOG" || log "!!! ${cov}x hap.py FAILED for $c"
  done

  # --- 4) collate per-depth SNP + INDEL rankings ---------------------------
  for TYPE in SNP INDEL; do
    OUT="$D/outputs/results/heldout_ranking_${TYPE}_${cov}x.tsv"
    printf "Depth\tCaller\tType\tTRUTH.TOTAL\tTP\tFN\tFP\tRecall\tPrecision\tF1\n" > "$OUT.tmp"
    for c in "${ORDER[@]}"; do
      s="$CDIR/${c}.summary.csv"; [ -s "$s" ] || continue
      awk -F',' -v C="$c" -v TY="$TYPE" -v CV="${cov}x" '
        NR==1{for(i=1;i<=NF;i++) h[$i]=i; next}
        $(h["Type"])==TY && $(h["Filter"])=="PASS"{
          printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n", CV,C,TY,
            $(h["TRUTH.TOTAL"]),$(h["TRUTH.TP"]),$(h["TRUTH.FN"]),$(h["QUERY.FP"]),
            $(h["METRIC.Recall"]),$(h["METRIC.Precision"]),$(h["METRIC.F1_Score"]) }' "$s" >> "$OUT.tmp" 2>/dev/null
    done
    { head -1 "$OUT.tmp"; tail -n +2 "$OUT.tmp" | sort -t$'\t' -k10,10gr; } > "$OUT"; rm -f "$OUT.tmp"
    log "wrote $OUT"
  done
done

echo "# STEP5c_coverage_DONE $(date '+%F %T')" >> "$D/params.txt"
log "===== STEP 5c coverage titration DONE ====="

# --- 5) accuracy-vs-coverage master table (SNP F1), incl. 70x from Step 5b ---
AVC="$D/outputs/results/accuracy_vs_coverage_heldout_SNP.tsv"
printf "Depth\tNewRetrainedDV\tStockDV\tFreebayes\tGatk\tBCF\tVarscan\n" > "$AVC"
f1(){ # $1=ranking file $2=caller  -> F1 or NA
  awk -F'\t' -v C="$2" '$2==C{print $10; found=1} END{if(!found)print "NA"}' "$1" 2>/dev/null | head -1; }
# 70x from s16 (no Depth col there -> caller in col1, F1 in col9)
S70="$D/outputs/results/heldout_ranking_SNP.tsv"
g70(){ awk -F'\t' -v C="$1" '$1==C{print $9}' "$S70" 2>/dev/null | head -1; }
printf "70x\t%s\t%s\t%s\t%s\t%s\t%s\n" "$(g70 NewRetrainedDV)" "$(g70 StockDV)" "$(g70 Freebayes)" "$(g70 Gatk)" "$(g70 BCF)" "$(g70 Varscan)" >> "$AVC"
for cov in 30 15 10; do
  RK="$D/outputs/results/heldout_ranking_SNP_${cov}x.tsv"
  [ -s "$RK" ] || continue
  printf "%sx\t%s\t%s\t%s\t%s\t%s\t%s\n" "$cov" "$(f1 "$RK" NewRetrainedDV)" "$(f1 "$RK" StockDV)" "$(f1 "$RK" Freebayes)" "$(f1 "$RK" Gatk)" "$(f1 "$RK" BCF)" "$(f1 "$RK" Varscan)" >> "$AVC"
done
echo "" | tee -a "$LOG"
echo "############ HELD-OUT SNP F1 vs COVERAGE (higher=better) ############" | tee -a "$LOG"
column -t -s$'\t' "$AVC" | tee -a "$LOG"
