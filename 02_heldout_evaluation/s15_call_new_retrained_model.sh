#!/usr/bin/env bash
# ============================================================================
# STEP 5a — Call the NEW simulation-truth retrained DeepVariant on the HELD-OUT
# test region ONLY (data_split/test.bed). This is the leakage-free test: the
# model was trained on train.bed, tuned on val.bed, and has NEVER seen test.bed.
#
# Uses EXACTLY the same run_deepvariant settings as the stock DV benchmark call
# (google/deepvariant:latest = v1.9.0, WGS, num_shards=80, same extra_args) so
# the ONLY difference vs stock is --customized_model (best ckpt = 37632, the
# epoch-6 checkpoint with the highest validation F1 0.99967). CPU vs GPU gives
# identical calls, so we match the stock run and use CPU. Resumable + logged.
# ============================================================================
set -uo pipefail
BASE="/home/work/Desktop/Fahad/03_Corrected_Work/rerun/09_simulation_truthset"
R="$BASE/RUN_DeepVariant_retraining"
D="$R/STEP5_heldout_test_evaluation"
G="$BASE/RUN_DeepVariant_fair_benchmark_simuG-ART/outputs"
REFDIR="$G/01_mutated_genome"                       # subset.fa (matches BAM+truth 100%)
BAMDIR="$G/03_aligned"
MODELDIR="$R/model/trained_model"                   # has example_info.json + checkpoints/ema/
CKPT="checkpoint-37632-0.99967-1"                    # best validation checkpoint (epoch 6)
TESTBED="$R/data_split/test.bed"
OUTDIR="$D/outputs/calls"
IMG="google/deepvariant:latest"                     # = v1.9.0 CPU (identical to stock run)
LOG="$D/run.log"; UG="$(id -u):$(id -g)"
mkdir -p "$OUTDIR"
log(){ echo "[$(date '+%F %T')] [s15] $*" | tee -a "$LOG"; }

OUT="NewRetrainedDV_test"
if [ -s "$OUTDIR/${OUT}.vcf.gz" ]; then
  log "$OUT already exists — skip (delete to re-run)."
else
  log "===== STEP 5a: call NEW sim-truth retrained DV on HELD-OUT test.bed ====="
  log "model=$MODELDIR/checkpoints/ema/$CKPT  regions=$TESTBED (52.0 Mb, 36 regions)"
  docker run --rm --user "$UG" \
    -v "$REFDIR":/ref:ro -v "$BAMDIR":/bam:ro -v "$MODELDIR":/model:ro \
    -v "$OUTDIR":/output -v "$R/data_split":/beds:ro \
    "$IMG" /opt/deepvariant/bin/run_deepvariant \
    --model_type=WGS \
    --customized_model=/model/checkpoints/ema/${CKPT} \
    --ref=/ref/subset.fa \
    --reads=/bam/sim.dedup.bam \
    --regions=/beds/test.bed \
    --output_vcf=/output/${OUT}.vcf.gz \
    --output_gvcf=/output/${OUT}.g.vcf.gz \
    --num_shards=80 \
    --intermediate_results_dir=/output/intermediates_${OUT} \
    --make_examples_extra_args="small_model_call_multiallelics=false" \
    2>&1 | tail -25 | tee -a "$LOG"
fi

if [ -s "$OUTDIR/${OUT}.vcf.gz" ]; then
  n=$(/home/work/miniconda3/envs/bcftools-env/bin/bcftools view -H "$OUTDIR/${OUT}.vcf.gz" 2>/dev/null | wc -l)
  log "STEP 5a DONE -> ${OUT}.vcf.gz ($n records)"
  rm -rf "$OUTDIR/intermediates_${OUT}"
  echo "# STEP5a_call_DONE $(date '+%F %T')" >> "$D/params.txt"
else
  log "ERROR: STEP 5a produced no VCF"; exit 3
fi
