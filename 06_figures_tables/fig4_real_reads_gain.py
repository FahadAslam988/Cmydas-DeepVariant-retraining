"""Fig 4: real reads of two green turtles (CH-NORMS1, Ab-NormS2), SNPs, leave-one-out (LOO) truth built without DeepVariant.
a = F1 difference, retrained minus default DeepVariant, with paired block-bootstrap 95% CI, for k = 2, 3, 4 and three regions
(WG = whole genome, TEST = held-out test contigs, UNUSED = contigs never used in training);
b = change in true positives and false positives (whole genome).
Sources: 03_tables/Bootstrap_bootstrap_pairwise_F1_diff.tsv; 03_tables/RealReads_<sample>_RetrainedDV2_vs_StockDV_LOO.tsv."""
import csv, os, numpy as np, matplotlib.pyplot as plt
from figstyle import *
H = os.path.dirname(os.path.abspath(__file__)); T = os.path.join(H, '..', '..', '03_tables')
df = list(csv.DictReader(open(f'{T}/Bootstrap_bootstrap_pairwise_F1_diff.tsv'), delimiter='\t'))
S = [('normal', 'CH-NORMS1', COL['RetrainedDV'], 'full'), ('abnormal', 'Ab-NormS2', COL['RetrainedDV'], 'none')]
REG = [('WG', 'Whole genome'), ('TEST', 'Test contigs'), ('UNUSED', 'Unused contigs')]
setup(); fig, (a, b) = plt.subplots(1, 2, figsize=(163 * MM, 78 * MM), gridspec_kw={'width_ratios': [1.45, 1], 'wspace': 0.42})
rows = [(k, r) for k in (2, 3, 4) for r in REG]; Y = np.arange(len(rows))[::-1].astype(float)
for k in (2, 3):  # light separators between k blocks
    a.axhline(Y[[i for i, (kk, _) in enumerate(rows) if kk == k][-1]] - 0.5, color='0.85', lw=0.6)
a.axvline(0, color='0.4', lw=0.8)
for off, (g, name, c, fill) in zip((0.15, -0.15), S):
    for y, (k, (reg, _)) in zip(Y, rows):
        r = next(r for r in df if r['Group'] == f'real_{g}_k{k}_{reg}_SNP' and r['CallerA'] == 'RetrainedDV2')
        m, lo, hi = float(r['F1_A_minus_B']), float(r['lo']), float(r['hi'])
        a.errorbar(m, y + off, xerr=[[m - lo], [hi - m]], fmt='s', color=c, mfc=c if fill == 'full' else 'white', ms=4,
                   elinewidth=0.9, capsize=1.6, label=name if (k, reg) == (2, 'WG') else None)
a.set_yticks(Y); a.set_yticklabels([f'k = {k}   {lab}' for k, (_, lab) in rows])
a.set_xlabel('F1 difference, retrained − default DeepVariant (95% CI)'); a.set_ylim(Y.min() - 0.6, Y.max() + 0.6)
clean(a, 'x'); letter(a, 'a', x=-0.42); a.legend(frameon=False, fontsize=FS_SMALL, loc='lower right')
# b: change in TP and FP, whole genome
W = 0.36; x = np.arange(3)
for j, (g, name, c, fill) in enumerate(S):
    rr = {(int(r['k']), r['Region'], r['Model']): r for r in csv.DictReader(open(f'{T}/RealReads_{name}_RetrainedDV2_vs_StockDV_LOO.tsv'), delimiter='\t')}
    dtp = [(int(rr[(k, 'WG', 'RetrainedDV2')]['TP']) - int(rr[(k, 'WG', 'StockDV')]['TP'])) / 1000 for k in (2, 3, 4)]
    dfp = [(int(rr[(k, 'WG', 'RetrainedDV2')]['FP']) - int(rr[(k, 'WG', 'StockDV')]['FP'])) / 1000 for k in (2, 3, 4)]
    xs = x + (j - 0.5) * W
    b.bar(xs, dtp, W * 0.92, color=COL['RetrainedDV'] if fill == 'full' else 'white', edgecolor=COL['RetrainedDV'], lw=0.8,
          label=f'{name}: true positives')
    b.bar(xs, [-v for v in dfp], W * 0.92, color='0.55' if fill == 'full' else 'white', edgecolor='0.45', lw=0.8, hatch=None if fill == 'full' else '////',
          label=f'{name}: false positives')
    for xi, v in zip(xs, dtp): b.text(xi, v + 3, f'+{v:.0f}', ha='center', va='bottom', fontsize=FS_SMALL - 0.5, color=GREY_TXT)
    for xi, v in zip(xs, dfp): b.text(xi, -v - 3, f'+{v:.0f}', ha='center', va='top', fontsize=FS_SMALL - 0.5, color=GREY_TXT)
b.axhline(0, color='0.4', lw=0.8); b.set_xticks(x); b.set_xticklabels(['k = 2', 'k = 3', 'k = 4'])
b.set_ylabel('Change vs default DeepVariant\n(thousands of SNPs, whole genome)')
yl = b.get_ylim(); b.set_ylim(yl[0] - 25, yl[1] + 25)
b.text(1.02, 0.97, 'more true\npositives', transform=b.transAxes, fontsize=FS_SMALL, va='top', color=GREY_TXT)
b.text(1.02, 0.03, 'more false\npositives', transform=b.transAxes, fontsize=FS_SMALL, va='bottom', color=GREY_TXT)
b.set_yticks(b.get_yticks()); b.set_yticklabels([f'{abs(t):.0f}' for t in b.get_yticks()])
clean(b, 'y'); letter(b, 'b', x=-0.3)
b.legend(frameon=False, fontsize=FS_SMALL - 0.5, loc='upper center', bbox_to_anchor=(0.5, -0.1), ncol=2)
save(fig, os.path.join(H, '..'), 'Fig4_real_reads_gain_two_genomes')
print('saved')
