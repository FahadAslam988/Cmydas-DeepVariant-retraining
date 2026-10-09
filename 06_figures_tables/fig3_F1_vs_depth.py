"""Fig 3: accuracy vs sequencing depth on the simulated held-out region (10, 15, 30, 70x).
a,b = error (1 - F1, log scale) of every caller, SNPs / indels; c,d = F1 difference vs default DeepVariant (paired 95% CI)
for the depth-matched retrained models and the 70x-trained model applied at lower depth.
Sources: 03_tables/Bootstrap_bootstrap_F1_CI.tsv and Bootstrap_bootstrap_pairwise_F1_diff.tsv.
At 70x the depth-matched model IS the 70x model (one model)."""
import csv, os, matplotlib.pyplot as plt
from matplotlib.ticker import FixedLocator, NullLocator
from figstyle import *
H = os.path.dirname(os.path.abspath(__file__)); T = os.path.join(H, '..', '..', '03_tables')
ci = list(csv.DictReader(open(f'{T}/Bootstrap_bootstrap_F1_CI.tsv'), delimiter='\t'))
df = list(csv.DictReader(open(f'{T}/Bootstrap_bootstrap_pairwise_F1_diff.tsv'), delimiter='\t'))
D = [10, 15, 30, 70]; X = range(len(D))
def f1(depth, t, c): return next(float(r['F1']) for r in ci if r['Group'] == f'sim_{depth}x_{t}' and r['Caller'] == c)
def diff(depth, t, a):
    r = next(r for r in df if r['Group'] == f'sim_{depth}x_{t}' and r['CallerA'] == a and r['CallerB'] == 'StockDV')
    return float(r['F1_A_minus_B']), float(r['lo']), float(r['hi'])
setup(); fig, axs = plt.subplots(2, 2, figsize=(170 * MM, 120 * MM), gridspec_kw={'hspace': 0.55, 'wspace': 0.32, 'height_ratios': [1.35, 1]})
for col, t in enumerate(['SNP', 'INDEL']):
    ax = axs[0, col]
    for c in ['Varscan', 'Gatk', 'BCF', 'Freebayes', 'StockDV', 'RetrainedDV']:
        src = (lambda d: 'RetrainedDV_sim') if c == 'RetrainedDV' else (lambda d, c=c: c)
        y = [1 - f1(d, t, src(d)) for d in D]
        ax.plot(X, y, marker=MK[c], color=COL[c], lw=2.0 if c == 'RetrainedDV' else 1.1, ms=4.5 if c == 'RetrainedDV' else 3.5,
                mec='white', mew=0.5, zorder=3 if c == 'RetrainedDV' else 2,
                label=(LABEL[c] + (' (depth-matched)' if c == 'RetrainedDV' else '')) if col == 0 else None)
    y70 = [1 - f1(d, t, 'RetrainedDV_sim_70xmodel') for d in D[:3]] + [1 - f1(70, t, 'RetrainedDV_sim')]
    ax.plot(X, y70, ls='--', color=COL['RetrainedDV'], lw=1.0, marker='s', mfc='white', ms=3.5, zorder=2,
            label='Retrained DeepVariant (70x-trained model)' if col == 0 else None)
    ax.set_yscale('log'); ax.set_xticks(list(X)); ax.set_xticklabels([f'{d}x' for d in D]); ax.set_xlim(-0.25, 3.25)
    ax.set_ylabel('Error, 1 − F1 (log scale)'); ax.set_xlabel('Sequencing depth'); clean(ax, 'y')
    ax.set_title('SNPs' if t == 'SNP' else 'Indels', fontsize=FS, fontweight='bold', loc='left'); letter(ax, 'ab'[col], x=-0.16)
    # c, d: difference vs default DV
    ax = axs[1, col]; ax.axhline(0, color='0.5', lw=0.8)
    for off, a, lab, filled in [(-0.09, 'RetrainedDV_sim', 'Depth-matched retrained model', True),
                                (0.09, 'RetrainedDV_sim_70xmodel', '70x-trained model used at lower depth', False)]:
        xs, ys, lo, hi = [], [], [], []
        for i, d in enumerate(D):
            if d == 70 and a.endswith('70xmodel'): continue
            m, l, h = diff(d, t, 'RetrainedDV_sim' if d == 70 else a)
            xs.append(i + (0 if d == 70 else off)); ys.append(m); lo.append(m - l); hi.append(h - m)
        ax.errorbar(xs, ys, yerr=[lo, hi], fmt='s', ls='-' if filled else '--', color=COL['RetrainedDV'], mfc=COL['RetrainedDV'] if filled else 'white',
                    ms=4, lw=1.2 if filled else 0.9, elinewidth=0.9, capsize=1.8, label=lab)
    ax.set_xticks(list(X)); ax.set_xticklabels([f'{d}x' for d in D]); ax.set_xlim(-0.25, 3.25)
    ax.set_ylabel('F1 difference vs\ndefault DeepVariant'); ax.set_xlabel('Sequencing depth'); clean(ax, 'y'); letter(ax, 'cd'[col], x=-0.16)
    if col == 0: ax.legend(frameon=False, fontsize=FS_SMALL, loc='upper left')
h, l = axs[0, 0].get_legend_handles_labels(); o = [5, 6, 4, 3, 2, 1, 0]
fig.legend([h[i] for i in o], [l[i] for i in o], loc='upper center', bbox_to_anchor=(0.5, 1.03), ncol=4, frameon=False, fontsize=FS_SMALL)
save(fig, os.path.join(H, '..'), 'Fig3_accuracy_vs_depth')
print('saved')
