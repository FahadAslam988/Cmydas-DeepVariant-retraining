#!/usr/bin/env bash
# Paper 2 (BMC Genomics): 95% CIs by PAIRED BLOCK BOOTSTRAP, same method as Paper 1
# (rerun/10_.../scripts/s06_bootstrap_ci.sh): 1,000 replicates, 1-Mb blocks, seed 20261001.
# Input = existing per-variant hap.py output VCFs (FORMAT/BD = TP/FP/FN, BVT = SNP/INDEL). Read-only; nothing is re-run.
# Groups (all callers in a group share the same block resampling = paired):
#   sim_<depth>_<SNP|INDEL> : simulated held-out test region, all callers (70x, 30x, 15x, 10x)
#   real_<sample>_k<k>_<region>_SNP : real reads, default vs retrained DV, LOO truth (k=2,3,4; WG/TEST/UNUSED)
# Check: totals recomputed from the VCFs must equal hap.py summary.csv (SNP/INDEL, ALL and PASS rows reported).
set -uo pipefail
R=/home/work/Desktop/Fahad/03_Corrected_Work/rerun
E=$R/11_Paper2_bootstrap_ci; D=$E/outputs; mkdir -p $D/blocks
BCF=/home/work/miniconda3/envs/bcftools-env/bin/bcftools
S5=$R/09_simulation_truthset/RUN_DeepVariant_retraining/STEP5_heldout_test_evaluation/outputs
AUG=$R/09_simulation_truthset/RUN_DeepVariant_coverage_augmented_retraining_mixed_10-15-30-70x/07_happy_benchmark_vs_truth
RR=$R/01_filtered/RetrainedDV2_real_reads/03_happy
LOG=$E/run.log; log(){ echo "[$(date '+%F %T')] $*" | tee -a "$LOG"; }
L=$D/runs.tsv; : > $L    # group  caller  hap.py-VCF  (summary.csv = same prefix)
for c in BCF Freebayes Gatk Varscan StockDV; do echo -e "sim_70x\t$c\t$S5/benchmark/$c.vcf.gz" >> $L; done
echo -e "sim_70x\tRetrainedDV_sim\t$S5/benchmark/NewRetrainedDV.vcf.gz" >> $L
for d in 30 15 10; do
  for c in BCF Freebayes Gatk Varscan StockDV; do echo -e "sim_${d}x\t$c\t$S5/coverage/${d}x/$c.vcf.gz" >> $L; done
  echo -e "sim_${d}x\tRetrainedDV_sim_70xmodel\t$S5/coverage/${d}x/NewRetrainedDV.vcf.gz" >> $L
  echo -e "sim_${d}x\tRetrainedDV_sim\t$AUG/happy_${d}x.vcf.gz" >> $L       # depth-matched model (run 3)
done
for g in normal abnormal; do for k in 2 3 4; do for reg in WG TEST UNUSED; do for m in StockDV RetrainedDV2; do
  echo -e "real_${g}_k${k}_${reg}\t$m\t$RR/${g}_k${k}_${reg}_${m}.vcf.gz" >> $L; done; done; done; done
log "runs: $(wc -l < $L)"
while IFS=$'\t' read -r grp c f; do [ -s "$f" ] || { log "MISSING $f"; exit 2; }; done < $L
# A) per-block counts per run: block  type  truthTP  FN  queryTP  FP
export BCF D
cut -f3 $L | xargs -P 40 -I{} bash -c 'f={}; o=$D/blocks/$(echo "$f" | md5sum | cut -c1-16).tsv; [ -s $o ] && exit 0
  $BCF query -f "%CHROM\t%POS[\t%BD\t%BVT]\n" "$f" 2>/dev/null | awk -F"\t" -v OFS="\t" "{b=\$1\":\"int(\$2/1000000)
    if(\$4==\"SNP\"||\$4==\"INDEL\"){k=b\"\t\"\$4; if(\$3==\"TP\")tt[k]++; else if(\$3==\"FN\")fn[k]++; K[k]=1}
    if(\$6==\"SNP\"||\$6==\"INDEL\"){k=b\"\t\"\$6; if(\$5==\"TP\")qt[k]++; else if(\$5==\"FP\")fp[k]++; K[k]=1}}
    END{for(k in K)print k,tt[k]+0,fn[k]+0,qt[k]+0,fp[k]+0}" > $o.tmp && mv $o.tmp $o'
log "block counts done"
# B) check + bootstrap
python3 - "$L" "$D" <<'PY' 2>&1 | tee -a "$LOG"
import sys,csv,hashlib,itertools,collections,numpy as np
L,D=sys.argv[1],sys.argv[2]; rng=np.random.default_rng(20261001); NB=1000
runs=collections.defaultdict(dict); chk=open(f'{D}/check_vs_happy_summary.tsv','w')
chk.write('Group\tCaller\tType\tTP_truth\tFN\tTP_query\tFP\tF1_recomputed\tF1_summary_ALL\tF1_summary_PASS\tmatch\n'); bad=0
for grp,cl,f in csv.reader(open(L),delimiter='\t'):
    h=hashlib.md5((f+'\n').encode()).hexdigest()[:16]
    rows=[r for r in csv.reader(open(f'{D}/blocks/{h}.tsv'),delimiter='\t')]
    summ={(r['Type'],r['Filter']):r for r in csv.DictReader(open(f[:-7]+'.summary.csv'))}
    types=['SNP'] if grp.startswith('real') else ['SNP','INDEL']
    for t in types:
        blk={r[0]:np.array(r[2:],float) for r in rows if r[1]==t}
        runs[f'{grp}_{t}'][cl]=blk
        tot=sum(blk.values()); p=tot[2]/(tot[2]+tot[3]); rc=tot[0]/(tot[0]+tot[1]); F=2*p*rc/(p+rc)
        fa=float(summ[(t,'ALL')]['METRIC.F1_Score']); fp_=float(summ[(t,'PASS')]['METRIC.F1_Score'])
        ok=abs(F-fa)<5e-6 or abs(F-fp_)<5e-6; bad+= not ok
        chk.write(f'{grp}\t{cl}\t{t}\t{int(tot[0])}\t{int(tot[1])}\t{int(tot[2])}\t{int(tot[3])}\t{F:.6f}\t{fa:.6f}\t{fp_:.6f}\t{"yes" if ok else "NO"}\n')
print('check mismatches:',bad)
def f1(c):
    p=c[...,2]/(c[...,2]+c[...,3]); r=c[...,0]/(c[...,0]+c[...,1]); return p,r,2*p*r/(p+r)
o1=open(f'{D}/bootstrap_F1_CI.tsv','w'); o1.write('Group\tCaller\tPrecision\tP_lo\tP_hi\tRecall\tR_lo\tR_hi\tF1\tF1_lo\tF1_hi\tTP\tFN\tFP\n')
o2=open(f'{D}/bootstrap_pairwise_F1_diff.tsv','w'); o2.write('Group\tCallerA\tCallerB\tF1_A_minus_B\tlo\thi\tShare_A_better\tCI_excludes_0\n')
o3=open(f'{D}/bootstrap_rank_stability.tsv','w'); o3.write('Group\tCaller\tRank\tShare_rank1\tMean_rank\tRank_lo\tRank_hi\n')
for key,cl in runs.items():
    names=list(cl); blocks=sorted(set().union(*[set(v) for v in cl.values()]))
    M=np.array([[cl[n].get(b,np.zeros(4)) for b in blocks] for n in names])
    idx=rng.integers(0,len(blocks),(NB,len(blocks)))
    W=np.stack([np.bincount(i,minlength=len(blocks)) for i in idx])
    tot=M.sum(1); bs=np.einsum('kb,nbc->knc',W,M)
    P,Rr,F=f1(tot); bp,br,bf=f1(bs)
    for j,n in enumerate(names):
        q=lambda a:np.percentile(a[:,j],[2.5,97.5])
        o1.write(f'{key}\t{n}\t{P[j]:.6f}\t'+'\t'.join(f'{x:.6f}' for x in q(bp))+f'\t{Rr[j]:.6f}\t'+'\t'.join(f'{x:.6f}' for x in q(br))
                 +f'\t{F[j]:.6f}\t'+'\t'.join(f'{x:.6f}' for x in q(bf))+f'\t{int(tot[j,0])}\t{int(tot[j,1])}\t{int(tot[j,3])}\n')
    for a,b in itertools.permutations(range(len(names)),2):
        if not (names[a].startswith('Retrained')): continue
        d=bf[:,a]-bf[:,b]; lo,hi=np.percentile(d,[2.5,97.5])
        o2.write(f'{key}\t{names[a]}\t{names[b]}\t{F[a]-F[b]:.6f}\t{lo:.6f}\t{hi:.6f}\t{(d>0).mean():.3f}\t{"yes" if lo>0 or hi<0 else "no"}\n')
    rk=(-bf).argsort(1).argsort(1)+1; r0=(-F).argsort().argsort()+1
    for j,n in enumerate(names):
        o3.write(f'{key}\t{n}\t{r0[j]}\t{(rk[:,j]==1).mean():.3f}\t{rk[:,j].mean():.2f}\t'+'\t'.join(str(int(x)) for x in np.percentile(rk[:,j],[2.5,97.5]))+'\n')
print('groups:',len(runs))
PY
[ "${PIPESTATUS[0]}" = 0 ] && log "bootstrap done: $D" || { log "ERROR in bootstrap step"; exit 3; }
