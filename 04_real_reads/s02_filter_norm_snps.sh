#!/usr/bin/env bash
# STEP 2 — process the new calls EXACTLY like the default DeepVariant calls of the companion study (filter, normalise, SNPs):
#   filter : (FILTER=PASS or .) && alt reads > 3 && VAF > 0.02         (stage1_filter.sh, EXPR_STD)
#   norm   : bcftools norm -f Reference.fasta -m -any -c w              (stage3_normalize_snps.sh)
#   SNPs   : bcftools view -v snps
set -uo pipefail
GRP="${1:-normal}"
BCF=/home/work/miniconda3/envs/bcftools-env/bin/bcftools     # v1.22, same as the companion study
E=/home/work/Desktop/Fahad/03_Corrected_Work/rerun/01_filtered/RetrainedDV2_real_reads
REF=/home/work/Desktop/DeepVariantTraining/ref/Reference.fasta
IN=$E/01_calls/RetrainedDV2_${GRP}.vcf.gz
D=$E/02_processed; mkdir -p "$D"; LOG=$E/run.log; T=16
log(){ echo "[$(date '+%F %T')] [s02 $GRP] $*" | tee -a "$LOG"; }
EXPR='(FILTER="PASS" || FILTER=".") && FMT/AD[0:1] > 3 && FMT/AD[0:1] / FMT/DP[0] > 0.02'
$BCF view --threads $T -i "$EXPR" "$IN" -Oz -o $D/RetrainedDV2_${GRP}.filtered.vcf.gz && $BCF index -f $D/RetrainedDV2_${GRP}.filtered.vcf.gz
$BCF norm -f $REF -m -any -c w --threads $T $D/RetrainedDV2_${GRP}.filtered.vcf.gz -Oz -o $D/RetrainedDV2_${GRP}.norm.vcf.gz 2>>"$LOG" && $BCF index -f $D/RetrainedDV2_${GRP}.norm.vcf.gz
$BCF view --threads $T -v snps $D/RetrainedDV2_${GRP}.norm.vcf.gz -Oz -o $D/RetrainedDV2_${GRP}_SNPs.vcf.gz && $BCF index -f -t $D/RetrainedDV2_${GRP}_SNPs.vcf.gz
log "raw=$($BCF view -H $IN | wc -l)  filtered=$($BCF index -n $D/RetrainedDV2_${GRP}.filtered.vcf.gz)  normSNPs=$($BCF index -n $D/RetrainedDV2_${GRP}_SNPs.vcf.gz)"
