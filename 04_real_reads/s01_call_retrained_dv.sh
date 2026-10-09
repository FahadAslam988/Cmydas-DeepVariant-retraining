#!/usr/bin/env bash
# ============================================================================
# STEP 1 — Call the Retraining-2 (simulation-truth) DeepVariant model on REAL reads, WHOLE GENOME.
# Same settings as the original stock real-read run (REAL_PIPELINE_COMMANDS.md):
#   DeepVariant v1.9.0, --model_type=WGS, same Reference.fasta, same dedup BAM,
#   --make_examples_extra_args="small_model_call_multiallelics=false".
# ONLY difference vs stock: --customized_model = best checkpoint 37632 (val F1 0.99967).
# num_shards only changes speed, not calls. CPU image used: the GPU image's TF 2.13 has no kernels for the RTX 5060 Ti (sm_120).
# Usage: ./s01_call_retrained_dv.sh normal            (whole genome; later: abnormal)
#        ./s01_call_retrained_dv.sh normal smoke      (5-min smoke test on 1 Mb, output *_smoke)
# ============================================================================
set -uo pipefail
GRP="${1:-normal}"
MODE="${2:-full}"
case $GRP in normal) SAMPLE=CH-NORMS1;; abnormal) SAMPLE=Ab-NormS2;; *) echo "use normal|abnormal"; exit 1;; esac

R=/home/work/Desktop/Fahad/03_Corrected_Work/rerun
E=$R/01_filtered/RetrainedDV2_real_reads
REFDIR=/home/work/Desktop/DeepVariantTraining/ref                          # Reference.fasta + .fai (read-only)
BAMDIR="/media/work/New Volume1/Varaint_moving/main data/variants/latest_tools_varains_with_reference_file/dedup_allignments"
MODELDIR=$R/09_simulation_truthset/RUN_DeepVariant_retraining/model/trained_model/checkpoints/ema
CKPT=checkpoint-37632-0.99967-1
OUTDIR=$E/01_calls
TMP="$E/tmp_intermediates_${GRP}_${MODE}"   # temp files on the ext4 home disk (2.8 TB free), deleted on success
IMG=google/deepvariant:latest     # = v1.9.0 CPU, identical image to the stock real-read run and the held-out sim test
LOG=$E/run.log
mkdir -p "$OUTDIR" "$TMP"
log(){ echo "[$(date '+%F %T')] [s01 $GRP] $*" | tee -a "$LOG"; }

OUT=RetrainedDV2_${GRP}; REGOPT=(); SHARDS=80
if [ "$MODE" = smoke ]; then OUT=RetrainedDV2_${GRP}_smoke; REGOPT=(--regions=NC_051264.2:5000001-6000000); SHARDS=8; fi
if [ -s "$OUTDIR/${OUT}.vcf.gz" ]; then log "$OUT exists — skip"; exit 0; fi

# ---- checks before a long run ----
# BAM index: Picard writes <name>.dedup.bai (htslib/DeepVariant also accept this name)
[ -s "$BAMDIR/${SAMPLE}.dedup.bam.bai" ] || [ -s "$BAMDIR/${SAMPLE}.dedup.bai" ] || { log "MISSING BAM index"; exit 2; }
for f in "$BAMDIR/${SAMPLE}.dedup.bam" "$REFDIR/Reference.fasta.fai" \
         "$MODELDIR/${CKPT}.index" "$MODELDIR/example_info.json"; do
  [ -s "$f" ] || { log "MISSING: $f"; exit 2; }
done
log "START whole-genome call  sample=$SAMPLE  model=$CKPT  image=$IMG"
docker run --rm --user "$(id -u):$(id -g)" \
  -v "$REFDIR":/ref:ro -v "$BAMDIR":/bam:ro -v "$MODELDIR":/model:ro \
  -v "$OUTDIR":/output -v "$TMP":/tmp_int \
  "$IMG" /opt/deepvariant/bin/run_deepvariant \
  --model_type=WGS \
  --customized_model=/model/${CKPT} \
  --ref=/ref/Reference.fasta \
  --reads=/bam/${SAMPLE}.dedup.bam \
  --output_vcf=/output/${OUT}.vcf.gz \
  --output_gvcf=/output/${OUT}.g.vcf.gz \
  --num_shards=$SHARDS "${REGOPT[@]}" \
  --intermediate_results_dir=/tmp_int \
  --make_examples_extra_args="small_model_call_multiallelics=false" \
  >> "$E/deepvariant_${GRP}_${MODE}.log" 2>&1
rc=$?
if [ $rc -eq 0 ] && [ -s "$OUTDIR/${OUT}.vcf.gz" ]; then
  n=$(/home/work/miniconda3/envs/bcftools-env/bin/bcftools view -H "$OUTDIR/${OUT}.vcf.gz" | wc -l)
  log "DONE -> ${OUT}.vcf.gz ($n records); removing intermediates"
  rm -rf "$TMP"
else
  log "ERROR rc=$rc (intermediates kept in $TMP for resume/debug)"; exit 3
fi
