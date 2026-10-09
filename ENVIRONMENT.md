# Software environment used for the analyses

| Tool | Version | Source |
|---|---|---|
| DeepVariant (calling) | 1.9.0 | Docker image google/deepvariant:latest (= 1.9.0, CPU) |
| DeepVariant (training) | 1.9.0 | Docker image google/deepvariant:1.9.0-gpu; warm start from the 1.9.0 WGS checkpoint |
| hap.py / RTG Tools (vcfeval) | 0.3.12 / 3.12.1 | Docker image jmcdani20/hap.py:v0.3.12 |
| BCFtools | 1.22 | conda |
| SAMtools | 1.10 (real reads), 1.19 (simulation) | conda |
| BWA-MEM | 0.7.17 (real reads), 0.7.18 (simulation) | conda |
| GATK | 4.6.2.0 | conda / Docker |
| FreeBayes, VarScan | 1.3.10, 2.4.6 | conda |
| ART (art_illumina) | 2016.06.05 | conda |
| Apache Beam (shuffling) | Python venv | pip |
| Python | 3, with numpy, matplotlib, python-docx, openpyxl | |

Hardware: 2 x Intel Xeon Gold 6138 (80 threads), 640 GB RAM, Ubuntu 24.04.
