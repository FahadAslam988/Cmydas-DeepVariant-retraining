#!/usr/bin/env bash
# STEP 4 — truth-free checks, stock vs retrained (whole genome + TEST region):
#   SNP count, Ti/Tv, het/hom-alt ratio, % of SNPs supported by >=1 of the other 4 callers, private SNPs.
set -uo pipefail
GRP="${1:-normal}"
BCF=/home/work/miniconda3/envs/bcftools-env/bin/bcftools
R=/home/work/Desktop/Fahad/03_Corrected_Work/rerun; E=$R/01_filtered/RetrainedDV2_real_reads
P=$E/03_happy/prep; D=$E/04_results; S=$D/stats_${GRP}; mkdir -p $S
declare -A Q=( [StockDV]=$R/04_norm_snps/Deepvariant_${GRP}_SNPs.vcf.gz
               [RetrainedDV2]=$E/02_processed/RetrainedDV2_${GRP}_SNPs.vcf.gz )
OTH=( $R/04_norm_snps/BCF_${GRP}_SNPs.vcf.gz $R/04_norm_snps/Freebayes_${GRP}_SNPs.vcf.gz
      $R/04_norm_snps/Gatk_${GRP}_SNPs.vcf.gz $R/04b_varscan_reheader/Varscan_${GRP}.vcf.gz )
# union of the other 4 callers' SNP sites
[ -s $S/others_union.vcf.gz ] || { $BCF merge -m none --force-samples -Ou "${OTH[@]}" | $BCF view -G -Oz -o $S/others_union.vcf.gz && $BCF index -f -t $S/others_union.vcf.gz; }
OUT=$D/sanity_${GRP}.tsv
printf "Region\tModel\tSNPs\tTiTv\tHet\tHomAlt\tHet/Hom\tSupported_by_other_callers_%%\tPrivate_SNPs\n" > $OUT
for reg in WG TEST; do for m in StockDV RetrainedDV2; do
  q=${Q[$m]}; ropt=(); [ $reg = TEST ] && ropt=(-R $P/TEST.bed)
  $BCF view "${ropt[@]}" -i 'GT="alt"' $q -Oz -o $S/${m}_${reg}.vcf.gz && $BCF index -f -t $S/${m}_${reg}.vcf.gz
  n=$($BCF index -n $S/${m}_${reg}.vcf.gz)
  titv=$($BCF stats $S/${m}_${reg}.vcf.gz | awk -F'\t' '$1=="TSTV"{print $5; exit}')
  het=$($BCF view -H -g het $S/${m}_${reg}.vcf.gz | wc -l); hom=$($BCF view -H -g hom $S/${m}_${reg}.vcf.gz | wc -l)
  sup=$($BCF isec -n=2 -w1 -c none $S/${m}_${reg}.vcf.gz $S/others_union.vcf.gz | grep -vc '^#')
  printf "%s\t%s\t%s\t%s\t%s\t%s\t%.3f\t%.2f\t%s\n" $reg $m $n $titv $het $hom $(echo "$het/$hom"|bc -l) $(echo "100*$sup/$n"|bc -l) $((n-sup)) >> $OUT
done; done
column -t $OUT
