"""Additional file figure: training curves and checkpoint selection for the four retrained models (70x, 30x, 15x, 10x).
Weighted F1 on training examples (grey) and on the validation contigs (blue, 37.7 Mb, never used for training) vs training
step; the selected checkpoint (highest validation F1, DeepVariant's rule best_checkpoint_metric = tune/f1_weighted) is marked.
Source: RERUN/09_simulation_truthset/RUN_DeepVariant_coverage_augmented_retraining_mixed_10-15-30-70x/
09_training_curves_and_checkpoint_selection/training_curves_all_depths.tsv (copied to 09_analysis_scripts_logs_results/05_...).
Step-0 validation entry (untrained evaluation, F1 ~0) is omitted."""
import csv, os, matplotlib.pyplot as plt
from figstyle import *
H = os.path.dirname(os.path.abspath(__file__)); P2 = os.path.join(H, '..', '..')
SRC = f'{P2}/09_analysis_scripts_logs_results/05_coverage_per_depth_retraining/09_training_curves_and_checkpoint_selection/training_curves_all_depths.tsv'
rows = list(csv.DictReader(open(SRC), delimiter='\t'))
SEL = {'70x': 37632, '30x': 56448, '15x': 37632, '10x': 25600}
setup(); fig, axs = plt.subplots(2, 2, figsize=(170 * MM, 105 * MM), gridspec_kw={'wspace': 0.3, 'hspace': 0.55}); axs = axs.ravel()
for ax, d, L in zip(axs, ['70x', '30x', '15x', '10x'], 'abcd'):
    for sp, c, lab in [('training', '0.45', 'Training'), ('validation', COL['RetrainedDV'], 'Validation')]:
        pts = sorted((int(r['step']), float(r['f1_weighted'])) for r in rows if r['depth'] == d and r['split'] == sp and int(r['step']) > 0)
        ax.plot([p[0] / 1000 for p in pts], [p[1] for p in pts], color=c, lw=1.0 if sp == 'training' else 1.3,
                marker='o' if sp == 'validation' else None, ms=2.5, label=lab)
    v = next(float(r['f1_weighted']) for r in rows if r['depth'] == d and r['split'] == 'validation' and int(r['step']) == SEL[d])
    ax.plot(SEL[d] / 1000, v, marker='*', ms=8, color=COL['RetrainedDV'], mec='white', mew=0.5, zorder=4)
    ax.axvline(SEL[d] / 1000, color=COL['RetrainedDV'], lw=0.6, ls=':')
    ax.set_title(f'{d} model', fontsize=FS, fontweight='bold', loc='left')
    ax.text(1.0, 1.02, f'selected: step {SEL[d]:,}, validation F1 {v:.5f}', transform=ax.transAxes, ha='right', va='bottom', fontsize=FS_SMALL, color=GREY_TXT); ax.set_xlabel('Training step (thousands)')
    if d in ('70x', '15x'): ax.set_ylabel('Weighted F1')
    clean(ax, 'y'); letter(ax, L, x=-0.13)
h, l = axs[0].get_legend_handles_labels()
from matplotlib.lines import Line2D
h.append(Line2D([], [], marker='*', ms=8, color=COL['RetrainedDV'], ls=':', lw=0.6)); l.append('Selected checkpoint')
fig.legend(h, l, loc='upper center', bbox_to_anchor=(0.5, 1.02), ncol=3, frameon=False, fontsize=FS_SMALL)
save(fig, os.path.join(H, '..'), 'FigS1_training_curves_checkpoint_selection')
print('saved')
