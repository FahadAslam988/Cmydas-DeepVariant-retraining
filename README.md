# Retraining DeepVariant with a simulation-derived truth set: green sea turtle (Chelonia mydas)

Code for the study "Retraining DeepVariant with a simulation-derived truth set improves variant calling in a
non-model vertebrate, the green sea turtle (Chelonia mydas)" (manuscript submitted to BMC Bioinformatics).

| Folder | Step |
|---|---|
| `01_retraining_70x/` | whole-contig train/validation/test split (s11), labelled examples with make_examples (s12), shuffling (s13), fine-tuning from the DeepVariant v1.9.0 WGS checkpoint (s14) |
| `02_heldout_evaluation/` | calling the held-out test contigs with the retrained model and scoring all callers with hap.py (s15-s17) |
| `03_depth_matched_models/` | down-sampling to 30x/15x/10x (s01), per-depth examples (s02), per-depth shuffling (s03b, run by s03c), training and checkpoint selection (s04), evaluation (s05) |
| `04_real_reads/` | retrained model on the real reads of CH-NORMS1 and Ab-NormS2 (s01), filtering (s02), hap.py against leave-one-out truth sets (s03), checks (s04) |
| `05_statistics/` | paired block bootstrap 95% confidence intervals |
| `06_figures_tables/` | figures, tables and additional files of the manuscript |

Data: raw reads NCBI SRA PRJNA1312993; reference GCF_015237465.2; simulated truth set and default call sets
https://doi.org/10.5281/zenodo.23088583; models and outputs of this study: [Zenodo DOI to be added].

Requirements: Linux, Docker, DeepVariant v1.9.0 Docker images, hap.py v0.3.12 (Docker), BCFtools v1.22, SAMtools, Python 3
(numpy, matplotlib, python-docx, openpyxl), Apache Beam (for shuffling). Paths at the top of each script refer to the
authors' workstation and must be adapted.

Note on this release: the scripts are those used for the analyses, with lines that processed an additional, earlier
model not reported in the manuscript removed. This does not change any result reported in the paper.

License: MIT (see LICENSE).
