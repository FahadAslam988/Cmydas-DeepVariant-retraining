"""Fig 2: F1 (95% bootstrap CI) of every caller on the simulated held-out region at 70x, SNPs (a) and indels (b).
Source: 03_tables/Bootstrap_bootstrap_F1_CI.tsv (groups sim_70x_SNP / sim_70x_INDEL)."""
import csv, os, matplotlib.pyplot as plt
from figstyle import *
H = os.path.dirname(os.path.abspath(__file__)); P2 = os.path.join(H, '..', '..')
rows = list(csv.DictReader(open(f'{P2}/03_tables/Bootstrap_bootstrap_F1_CI.tsv'), delimiter='\t'))
ren = {'RetrainedDV_sim': 'RetrainedDV'}
setup(); fig, axs = plt.subplots(1, 2, figsize=(158 * MM, 55 * MM), sharey=True, gridspec_kw={'wspace': 0.12})
for ax, t, L in zip(axs, ['SNP', 'INDEL'], 'ab'):
    d = {ren.get(r['Caller'], r['Caller']): r for r in rows if r['Group'] == f'sim_70x_{t}'}
    names = ORDER[::-1]  # same order in both panels, retrained on top next to default
    for i, n in enumerate(names):
        f, lo, hi = (float(d[n][k]) for k in ('F1', 'F1_lo', 'F1_hi'))
        ax.errorbar(f, i, xerr=[[f - lo], [hi - f]], fmt=MK[n], color=COL[n], ms=4.5 if n != 'RetrainedDV' else 5.5,
                    mec='white' if n != 'RetrainedDV' else COL[n], mew=0.6, elinewidth=1.0, capsize=1.8)
        ax.text(hi, i, f'  {f:.4f}', va='center', fontsize=FS_SMALL, color=GREY_TXT)
    ax.set_yticks(range(len(names))); ax.set_yticklabels([LABEL[n] for n in names])
    for tl, n in zip(ax.get_yticklabels(), names): tl.set_fontweight('bold' if n == 'RetrainedDV' else 'normal')
    lo_all = min(float(d[n]['F1_lo']) for n in names); hi_all = max(float(d[n]['F1_hi']) for n in names)
    ax.set_xlim(lo_all - 0.0008, hi_all + 0.0012); ax.set_ylim(-0.6, len(names) - 0.4)
    from matplotlib.ticker import MultipleLocator
    ax.xaxis.set_major_locator(MultipleLocator(0.002 if t == 'SNP' else 0.005))
    ax.set_xlabel('F1 score (95% CI)'); clean(ax); letter(ax, L, x=-0.62 if L == 'a' else -0.04)
    ax.set_title('SNPs' if t == 'SNP' else 'Indels', fontsize=FS, fontweight='bold', loc='left')
save(fig, os.path.join(H, '..'), 'Fig2_F1_70x_all_callers_CI')
print('saved')
