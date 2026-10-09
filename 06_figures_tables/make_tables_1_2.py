"""Paper 2 Tables 1 and 2 (BMC rules: table object, title <= 15 words above, legend below, no colour, no commas in numbers).
All values read from source files at run time.
Outputs: 03_tables/Table1_data_truth_sets_models.tsv, Table2_default_vs_retrained.tsv, 01_manuscript_drafts/Paper2_Tables_V<N>.docx"""
import csv, os, sys, subprocess
from decimal import Decimal, ROUND_HALF_UP
from docx import Document
from docx.shared import Pt
from docx.enum.text import WD_ALIGN_PARAGRAPH
H = os.path.dirname(os.path.abspath(__file__)); T = os.path.join(H, '..'); P2 = os.path.join(T, '..')
V = sys.argv[1] if len(sys.argv) > 1 else '1'
R = '/home/work/Desktop/Fahad/03_Corrected_Work/rerun'
def r(x, n=4): return str(Decimal(str(x)).quantize(Decimal(1).scaleb(-n), ROUND_HALF_UP))
def num(n): return f'{int(n):,}'.replace(',', '\u00a0')  # non-breaking space: no commas (BMC), never split          # BMC: no commas in numbers -> thin spacing by space
def tsv(p): return list(csv.DictReader(open(p), delimiter='\t'))
# ---------- Table 1 ----------
split = {}
for s in ('train', 'val', 'test'):
    b = f'{R}/09_simulation_truthset/RUN_DeepVariant_retraining/data_split/{s}.bed'
    rows = [l.split() for l in open(b) if l.strip()]
    nv = subprocess.run(f"/home/work/miniconda3/envs/bcftools-env/bin/bcftools view -H -R {b} {R}/09_simulation_truthset/RUN_DeepVariant_fair_benchmark_simuG-ART/outputs/01_mutated_genome/truth.vcf.gz 2>/dev/null | wc -l", shell=True, capture_output=True, text=True).stdout.strip()
    split[s] = (len({x[0] for x in rows}), sum(int(x[2]) - int(x[1]) for x in rows) / 1e6, int(nv))
loo = {}
for g, name in (('normal', 'CH-NORMS1'), ('abnormal', 'Ab-NormS2')):
    for x in tsv(f'{T}/RealReads_{name}_RetrainedDV2_vs_StockDV_LOO.tsv'):
        if x['Region'] == 'WG' and x['Model'] == 'StockDV': loo[(name, x['k'])] = int(x['TP']) + int(x['FN'])
T1 = [('Data set', 'Content', 'Use'),
      ('Real genomes', f'Two green turtles (CH-NORMS1, Ab-NormS2); Illumina NovaSeq 6000, 2 x 151 bp; {num(456923725)} and {num(441497634)} read pairs; mapped depth after duplicate removal 56.05x and 57.96x', 'Real-read validation (SNPs)'),
      ('Reference genome', 'rCheMyd1.pri.v2 (GCF_015237465.2); simulation restricted to 72 contigs, 210.8 Mb callable sequence', 'Simulation'),
      ('Simulated truth set', f'{num(1227026)} SNVs and {num(153429)} indels planted in the 72 contigs; density, Ti/Tv and heterozygosity calibrated to the real genomes; ART reads at 69.71x, down-sampled to 30x, 15x and 10x', 'Training, validation, testing'),
      ('Training contigs', f'{split["train"][0]} contigs, {split["train"][1]:.1f} Mb, {num(split["train"][2])} variants', 'Model training'),
      ('Validation contigs', f'{split["val"][0]} contigs, {split["val"][1]:.1f} Mb, {num(split["val"][2])} variants', 'Checkpoint selection'),
      ('Test contigs (held out)', f'{split["test"][0]} contigs, {split["test"][1]:.1f} Mb, {num(split["test"][2])} variants', 'Accuracy, all callers and depths'),
      ('Leave-one-out truth sets', 'SNPs called by at least k of BCFtools, FreeBayes, GATK and VarScan (DeepVariant excluded); ' +
        '; '.join(f'k = {k}: {num(loo[("CH-NORMS1", k)])} / {num(loo[("Ab-NormS2", k)])}' for k in ('2', '3', '4')) + ' SNPs (CH-NORMS1 / Ab-NormS2)', 'Real-read validation'),
      ('Models', 'Default DeepVariant v1.9.0 (WGS model); retrained models fine-tuned from it at 70x, 30x, 15x and 10x', 'Compared with BCFtools, FreeBayes, GATK, VarScan')]
with open(f'{T}/Table1_data_truth_sets_models.tsv', 'w') as f:
    for row in T1: f.write('\t'.join(row) + '\n')
# ---------- Table 2 ----------
ci = tsv(f'{T}/Bootstrap_bootstrap_F1_CI.tsv'); df = tsv(f'{T}/Bootstrap_bootstrap_pairwise_F1_diff.tsv')
def g(group, caller): return next(x for x in ci if x['Group'] == group and x['Caller'] == caller)
def d(group, a): return next(x for x in df if x['Group'] == group and x['CallerA'] == a and x['CallerB'] == 'StockDV')
T2 = [('Data', 'Variant type', 'Default DV F1', 'Retrained DV F1', 'Difference (95% CI)', 'Precision, default / retrained', 'Recall, default / retrained')]
def line(lab, t, grp, a):
    s, n, x = g(grp, 'StockDV'), g(grp, a), d(grp, a)
    T2.append((lab, t, r(s['F1']), r(n['F1']), f"{r(x['F1_A_minus_B'])} ({r(x['lo'])} to {r(x['hi'])})",
               f"{r(s['Precision'])} / {r(n['Precision'])}", f"{r(s['Recall'])} / {r(n['Recall'])}"))
for dep in (70, 30, 15, 10):
    for t in ('SNP', 'INDEL'): line(f'Simulated test contigs, {dep}x', 'SNP' if t == 'SNP' else 'Indel', f'sim_{dep}x_{t}', 'RetrainedDV_sim')
for name, gname in (('CH-NORMS1', 'normal'), ('Ab-NormS2', 'abnormal')):
    for k in (2, 3, 4): line(f'{name}, real reads, LOO k = {k}', 'SNP', f'real_{gname}_k{k}_WG_SNP', 'RetrainedDV2')
with open(f'{T}/Table2_default_vs_retrained.tsv', 'w') as f:
    for row in T2: f.write('\t'.join(row) + '\n')
# ---------- DOCX ----------
doc = Document(); st = doc.styles['Normal']; st.font.name = 'Arial'; st.font.size = Pt(9)
from docx.shared import Cm
def table(title, rows, legend, widths):
    p = doc.add_paragraph(); run = p.add_run(title); run.bold = True
    t = doc.add_table(rows=len(rows), cols=len(rows[0])); t.style = 'Table Grid'; t.autofit = False
    for j, w in enumerate(widths): t.columns[j].width = Cm(w)
    for i, row in enumerate(rows):
        for j, v in enumerate(row):
            c = t.cell(i, j); c.text = v; c.width = Cm(widths[j])
            for pp in c.paragraphs:
                for rr in pp.runs: rr.font.size = Pt(8); rr.bold = (i == 0)
    doc.add_paragraph(legend).runs[0].font.size = Pt(8); doc.add_paragraph()
table('Table 1 Data sets, truth sets and models used in this study', T1,
      'Mb, megabases; SNV, single-nucleotide variant; LOO, leave-one-out; k, minimum number of the four other callers that must report a SNP for it to enter the truth set. '
      'Simulated variant counts per set were counted in the truth VCF within each set of contigs. LOO truth-set sizes are for the whole genome.', [3.2, 10.0, 3.8])
table('Table 2 Accuracy of default and retrained DeepVariant on simulated and real reads', T2,
      'DV, DeepVariant; LOO, leave-one-out truth built without DeepVariant (whole genome). Simulated data: the retrained model is the one trained at the same depth '
      '(at 70x, the 70x model); scored at genotype level on the 52.0 Mb test contigs. Real reads: SNPs scored at allele level. Difference = retrained minus default F1 with '
      '95% confidence interval from a paired block bootstrap (1-Mb blocks, 1000 replicates).', [3.6, 1.4, 1.6, 1.7, 3.2, 2.3, 2.3])
out = f'{P2}/01_manuscript_drafts/Paper2_Tables_V{V}.docx'; doc.save(out); print('saved', out)
