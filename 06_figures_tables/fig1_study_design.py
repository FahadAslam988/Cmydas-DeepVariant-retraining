"""Fig 1: study design. a simulation + leakage-free whole-contig split; b retraining; c evaluation.
Numbers verified 2026-10-09 from source files: split BEDs (RERUN/09_simulation_truthset/RUN_DeepVariant_retraining/data_split),
truth.vcf.gz (1,227,026 SNVs + 153,429 indels; per-split counts by bcftools -R), training script s14 (WGS warm start,
10 epochs, batch 128, lr 1e-4), best checkpoint 37632 (validation F1 0.99967)."""
import os, matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, Rectangle
from figstyle import *
H = os.path.dirname(os.path.abspath(__file__))
BOX, EDGE, ACC = '#F2F4F7', '#8A8F98', COL['RetrainedDV']
setup(); fig = plt.figure(figsize=(164 * MM, 112 * MM)); ax = fig.add_axes([0, 0, 1, 1]); ax.set_xlim(-1, 177); ax.set_ylim(0, 112); ax.axis('off')
def box(x, y, w, h, title, body='', fc=BOX, ec=EDGE, bold_col='#1F1F1F'):
    ax.add_patch(FancyBboxPatch((x, y), w, h, boxstyle='round,pad=0,rounding_size=1.2', fc=fc, ec=ec, lw=0.8))
    ax.text(x + w / 2, y + h - 2.2, title, ha='center', va='top', fontsize=FS, fontweight='bold', color=bold_col)
    if body: ax.text(x + w / 2, y + h - 6.4, body, ha='center', va='top', fontsize=FS_SMALL, color=GREY_TXT, linespacing=1.25)
def arrow(x0, y0, x1, y1): ax.annotate('', (x1, y1), (x0, y0), arrowprops=dict(arrowstyle='-|>', color='#5A5F68', lw=0.9, mutation_scale=7))
def sec(x, y, s, t): ax.text(x, y, s, fontsize=FS_LETTER, fontweight='bold', va='bottom'); ax.text(x + 4, y + 0.3, t, fontsize=FS, fontweight='bold', va='bottom', color=NAVY)
# a: simulation
sec(2, 104, 'a', 'Simulated training and test data')
box(4, 82, 36, 19, 'Reference genome', '$\\it{C.}$ $\\it{mydas}$ rCheMyd1.pri.v2\n72 contigs, 210.8 Mb\ncallable sequence')
box(48, 82, 44, 19, 'Simulated variants', '1,227,026 SNVs + 153,429 indels\ndensity, Ti/Tv and het:hom\ncalibrated to the real genomes')
box(100, 82, 66, 19, 'Simulated short reads (ART)', '2 x 151 bp; error profile and insert size\nlearned from the real reads\n~70x, downsampled to 30x, 15x, 10x')
arrow(40, 91.5, 48, 91.5); arrow(92, 91.5, 100, 91.5)
# split bar (proportional to Mb)
y0, h0, x0, W = 68, 6, 4, 162; tot = 210.8
parts = [('Training', 121.1, 41, 792886, ACC, 'white'), ('Validation', 37.7, 15, 246769, '#6BAED6', '#1F1F1F'),
         ('Test (held out)', 52.0, 16, 340800, 'white', '#1F1F1F')]
x = x0
for name, mb, nc, nv, fc, tc in parts:
    w = W * mb / tot
    ax.add_patch(Rectangle((x, y0), w, h0, fc=fc, ec=ACC, lw=0.9, hatch='////' if fc == 'white' else None))
    ax.text(x + w / 2, y0 + h0 / 2, name, ha='center', va='center', fontsize=FS_SMALL, color=tc, fontweight='bold',
            bbox=dict(fc='white', ec='none', pad=0.8) if fc == 'white' else None)
    ax.text(x + w / 2, y0 - 1.2, f'{nc} contigs, {mb:.1f} Mb\n{nv:,} simulated variants', ha='center', va='top', fontsize=FS_SMALL, color=GREY_TXT)
    x += w
ax.text(x0, y0 + h0 + 1.2, 'Leakage-free split by whole contigs (no read crosses a boundary)', fontsize=FS_SMALL, color=GREY_TXT, va='bottom')
arrow(88, 82, 88, 75.5)
# b: training
sec(2, 52, 'b', 'Retraining DeepVariant')
box(4, 34, 50, 16, 'Default DeepVariant v1.9.0', 'WGS model (trained on\nhuman data)')
box(62, 34, 50, 16, 'Fine-tuning on training contigs', '10 epochs, batch 128,\nlearning rate 1e-4')
box(120, 34, 46, 16, 'Retrained model', 'best checkpoint by validation F1\n(0.99967); also models\ntrained at 30x, 15x, 10x', fc='#E3EEF8', ec=ACC, bold_col=ACC)
arrow(54, 42, 62, 42); arrow(112, 42, 120, 42)
# c: evaluation
sec(2, 27, 'c', 'Evaluation against default DeepVariant and four other callers')
box(4, 6, 78, 18, 'Simulated test contigs (exact truth)', 'never used in training or model selection\n70x, 30x, 15x, 10x; SNPs and indels\nFigs. 2 and 3')
box(88, 6, 78, 18, 'Real reads of two green turtles', 'CH-NORMS1 and Ab-NormS2 (56x and 58x), SNPs\nleave-one-out truth from BCFtools, FreeBayes,\nGATK and VarScan (k = 2, 3, 4); Fig. 4')
ax.text(85, 1.2, 'Scoring: hap.py v0.3.12 (simulation: genotype-level, test contigs; real reads: allele-level, vcfeval); 95% CIs by paired block bootstrap',
        ha='center', va='bottom', fontsize=FS_SMALL, color=GREY_TXT)
# no connector arrows in c (heading carries the flow; arrows crossed the heading)
save(fig, os.path.join(H, '..'), 'Fig1_study_design')
print('saved')
