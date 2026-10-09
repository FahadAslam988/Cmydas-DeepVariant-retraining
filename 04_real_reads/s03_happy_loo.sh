#!/usr/bin/env bash
# STEP 3 — score STOCK DV (default DeepVariant calls, 04_norm_snps) vs RETRAINED DV2 (new) against the SAME
# leave-one-out truth built WITHOUT DeepVariant (>=k of BCFtools/FreeBayes/GATK/VarScan), k = 2,3,4.
# Identical hap.py settings to stage5_leaveoneout_happy.sh / 08_retrain_eval:
#   hap.py v0.3.12, --engine=vcfeval, --set-gt hom (allele-level), 0/0 and ./. removed first.
# Three regions (all cut from the SAME whole-genome calls):
#   WG      = whole genome
#   TEST    = Retraining-2 held-out test.bed (same region as the simulation held-out result)
#   UNUSED  = contigs never used in Retraining 2 at all (not in train/val/test split)
set -uo pipefail
GRP="${1:-normal}"
BCF=/home/work/miniconda3/envs/bcftools-env/bin/bcftools
R=/home/work/Desktop/Fahad/03_Corrected_Work/rerun; E=$R/01_filtered/RetrainedDV2_real_reads
DESK=/home/work/Desktop; REFDIR=$DESK/DeepVariantTraining/ref
SPLIT=$R/09_simulation_truthset/RUN_DeepVariant_retraining/data_split
H=$E/03_happy; P=$H/prep; mkdir -p "$P"; LOG=$E/run.log
IMG=jmcdani20/hap.py:v0.3.12; THREADS=8; MAXPAR=6
c(){ echo "/data/${1#$DESK/}"; }
log(){ echo "[$(date '+%F %T')] [s03 $GRP] $*" | tee -a "$LOG"; }

# region BEDs
cp $SPLIT/test.bed $P/TEST.bed
awk -v OFS='\t' '{print $1,0,$2}' $REFDIR/Reference.fasta.fai > $P/WG.bed
cat $SPLIT/train.contigs $SPLIT/val.contigs $SPLIT/test.contigs | sort -u > $P/used.contigs
awk -v OFS='\t' 'NR==FNR{u[$1]=1;next} !($1 in u){print $1,0,$2}' $P/used.contigs $REFDIR/Reference.fasta.fai > $P/UNUSED.bed

tsrc(){ case $1 in 2) echo $R/06_loo/${GRP}_leaveout_Deepvariant/truth_${GRP}_wo_Deepvariant.vcf.gz;;
                   3) echo $R/07_loo_sensitivity/k3_ge3_of4/truth/truth_${GRP}_wo_Deepvariant.vcf.gz;;
                   4) echo $R/07_loo_sensitivity/k4_eq4_of4/truth/truth_${GRP}_wo_Deepvariant.vcf.gz;; esac; }
declare -A Q=( [StockDV]=$R/04_norm_snps/Deepvariant_${GRP}_SNPs.vcf.gz
               [RetrainedDV2]=$E/02_processed/RetrainedDV2_${GRP}_SNPs.vcf.gz )
# alt-only copies (as stage5)
for k in 2 3 4; do $BCF view -i 'GT="alt"' "$(tsrc $k)" -Oz -o $P/truth_k${k}.vcf.gz && $BCF index -f -t $P/truth_k${k}.vcf.gz; done
for m in StockDV RetrainedDV2; do $BCF view -i 'GT="alt"' "${Q[$m]}" -Oz -o $P/q_${m}.vcf.gz && $BCF index -f -t $P/q_${m}.vcf.gz; done

run(){ local k=$1 reg=$2 m=$3 pfx=$H/${GRP}_k${1}_${2}_${3}
  [ -s $pfx.summary.csv ] && return 0
  docker run --rm -u "$(id -u):$(id -g)" -e HOME="$(c $H)" -v "$DESK":/data "$IMG" /opt/hap.py/bin/hap.py \
    "$(c $P/truth_k${k}.vcf.gz)" "$(c $P/q_${m}.vcf.gz)" -r "$(c $REFDIR/Reference.fasta)" -o "$(c $pfx)" \
    -T "$(c $P/${reg}.bed)" --engine=vcfeval --engine-vcfeval-template "$(c $REFDIR/Reference.sdf)" \
    --set-gt hom --threads $THREADS --scratch-prefix "$(c $P)" >>"$H/happy_${GRP}.log" 2>&1
  log "hap.py k=$k $reg $m rc=$?"; }
for k in 2 3 4; do for reg in WG TEST UNUSED; do for m in StockDV RetrainedDV2; do
  run $k $reg $m & while [ "$(jobs -rp|wc -l)" -ge $MAXPAR ]; do wait -n; done
done; done; done; wait

OUT=$E/04_results/happy_loo_${GRP}.tsv; mkdir -p $E/04_results
printf "k\tRegion\tModel\tTP\tFP\tFN\tPrecision\tRecall\tF1\n" > $OUT
for k in 2 3 4; do for reg in WG TEST UNUSED; do for m in StockDV RetrainedDV2; do
  awk -F',' -v k=$k -v r=$reg -v m=$m 'NR==1{for(i=1;i<=NF;i++)h[$i]=i;next} $h["Type"]=="SNP"&&$h["Filter"]=="ALL"{
    printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n",k,r,m,$h["TRUTH.TP"],$h["QUERY.FP"],$h["TRUTH.FN"],$h["METRIC.Precision"],$h["METRIC.Recall"],$h["METRIC.F1_Score"]}' \
    $H/${GRP}_k${k}_${reg}_${m}.summary.csv >> $OUT
done; done; done
log "results -> $OUT"; column -t $OUT
