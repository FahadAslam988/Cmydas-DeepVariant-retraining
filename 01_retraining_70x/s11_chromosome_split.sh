#!/usr/bin/env bash
# ============================================================================
# STEP 1 (retraining) — STRATIFIED leakage-free split of the 72 contigs into
# TRAIN / VALIDATION / TEST (~60/20/20). Whole contigs (no boundary-spanning
# reads). To make each set REPRESENTATIVE (Whalen et al. 2022): distribute the
# repeat-rich small scaffolds by COUNT (60/20/20) so every set gets them, then
# place large + mid contigs to balance total bp. Chromosome hold-out as in
# TrioTrain (Kalleberg 2025) / GIAB. Deterministic.
# ============================================================================
set -uo pipefail
G="/home/work/Desktop/Fahad/03_Corrected_Work/rerun/09_simulation_truthset/RUN_DeepVariant_fair_benchmark_simuG-ART/outputs/01_mutated_genome"
R="/home/work/Desktop/Fahad/03_Corrected_Work/rerun/09_simulation_truthset/RUN_DeepVariant_retraining"
FAI="$G/subset.fa.fai"; CALL="$G/callable.bed"; OUT="$R/data_split"
mkdir -p "$OUT"

python3 - "$FAI" "$CALL" "$OUT" <<'PY'
import sys
fai, call, out = sys.argv[1], sys.argv[2], sys.argv[3]
cbp={}
for ln in open(call):
    c,s,e=ln.split()[:3]; cbp[c]=cbp.get(c,0)+(int(e)-int(s))
total=sum(cbp.values())
big=[c for c in cbp if cbp[c]>=5e6]           # large+mid chromosomes (bp matters)
small=[c for c in cbp if cbp[c]<5e6]           # repeat-rich unplaced scaffolds (count matters)
big.sort(key=lambda c:-cbp[c]); small.sort(key=lambda c:-cbp[c])
cur={"train":0,"val":0,"test":0}; assign={}
# 1) small scaffolds by COUNT -> 60/20/20 (every set gets repeat-rich contigs)
tcnt={"train":0.60*len(small),"val":0.20*len(small),"test":0.20*len(small)}; ccnt={"train":0,"val":0,"test":0}
for c in small:
    s=max(ccnt, key=lambda k:tcnt[k]-ccnt[k]); assign[c]=s; ccnt[s]+=1; cur[s]+=cbp[c]
# 2) large+mid by remaining bp deficit -> hit 60/20/20 total
tbp={"train":0.60*total,"val":0.20*total,"test":0.20*total}
for c in big:
    s=max(cur, key=lambda k:tbp[k]-cur[k]); assign[c]=s; cur[s]+=cbp[c]
# outputs
contigs=sorted(cbp,key=lambda c:-cbp[c])
def cls(bp): return "large" if bp>=50e6 else ("mid" if bp>=5e6 else "small")
lists={k:open(f"{out}/{k}.contigs","w") for k in cur}; beds={k:open(f"{out}/{k}.bed","w") for k in cur}
setn={k:{"large":0,"mid":0,"small":0} for k in cur}; setbp={k:0 for k in cur}
for c in contigs: lists[assign[c]].write(c+"\n"); setn[assign[c]][cls(cbp[c])]+=1; setbp[assign[c]]+=cbp[c]
for ln in open(call): beds[assign[ln.split()[0]]].write(ln)
for f in list(lists.values())+list(beds.values()): f.close()
print(f"{'set':<6}{'Mb':>8}{'pct':>7}{'large':>7}{'mid':>6}{'small':>7}")
for k in ("train","val","test"):
    n=setn[k]; print(f"{k:<6}{setbp[k]/1e6:>8.1f}{100*setbp[k]/total:>6.1f}%{n['large']:>7}{n['mid']:>6}{n['small']:>7}")
print(f"total {total/1e6:.1f} Mb / {len(contigs)} contigs")
PY
echo "written: $OUT/{train,val,test}.{bed,contigs}"