"""Shared style for every Paper 2 figure (same system as Paper 1: Okabe-Ito, 7 pt sans-serif, white background).
Palette validated 2026-10-09 (dataviz validate_palette.js, light): all checks pass; CVD pair BCF/GATK-FreeBayes in the 6-8 band
-> every caller also has its own marker + direct label."""
import matplotlib
from matplotlib import font_manager
NAVY, GREY_TXT = '#08519C', '#3A3A3A'
ORDER = ['RetrainedDV', 'StockDV', 'Freebayes', 'BCF', 'Gatk', 'Varscan']
LABEL = {'RetrainedDV': 'Retrained DeepVariant', 'StockDV': 'Default DeepVariant', 'Freebayes': 'FreeBayes',
         'BCF': 'BCFtools', 'Gatk': 'GATK', 'Varscan': 'VarScan', 'RetrainedDV70': 'Retrained DeepVariant (70x model)'}
COL = {'RetrainedDV': '#0072B2', 'StockDV': '#56B4E9', 'Freebayes': '#009E73', 'BCF': '#E69F00', 'Gatk': '#CC79A7',
       'Varscan': '#D55E00', 'RetrainedDV70': '#0072B2'}
MK = {'RetrainedDV': 's', 'StockDV': 'o', 'Freebayes': '^', 'BCF': 'P', 'Gatk': 'D', 'Varscan': 'v', 'RetrainedDV70': 's'}
FS, FS_SMALL, FS_LETTER = 7, 6, 9
MM = 1 / 25.4
def setup():
    fam = 'Arial' if any('Arial' in f.name for f in font_manager.fontManager.ttflist) else 'Liberation Sans'
    matplotlib.rcParams.update({'font.family': fam, 'font.size': FS, 'axes.linewidth': 0.8, 'pdf.fonttype': 42, 'ps.fonttype': 42,
        'xtick.major.width': 0.8, 'ytick.major.width': 0.8, 'axes.labelcolor': '#1F1F1F', 'text.color': '#1F1F1F',
        'xtick.labelsize': FS_SMALL, 'ytick.labelsize': FS,
        'mathtext.fontset': 'custom', 'mathtext.it': f'{fam}:italic', 'mathtext.rm': fam})  # species names in the same font
def clean(ax, axis='x'):
    ax.spines[['top', 'right']].set_visible(False)
    ax.grid(axis=axis, color='0.92', lw=0.6); ax.set_axisbelow(True)
def letter(ax, s, x=-0.02, y=1.02):
    ax.text(x, y, s, transform=ax.transAxes, fontweight='bold', fontsize=FS_LETTER, va='bottom', ha='right')
def save(fig, out, name):
    for ext, kw in (('pdf', {}), ('tiff', {'dpi': 300, 'pil_kwargs': {'compression': 'tiff_lzw'}}), ('png', {'dpi': 300})):
        fig.savefig(f'{out}/{name}.{ext}', bbox_inches='tight', facecolor='white', **kw)
