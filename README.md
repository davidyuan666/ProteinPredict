# ColabFold GPU Predict Pipeline

一键安装 + 预测 + 打包，支持 GPU 服务器本地运行。

## 硬件要求

| 显卡 | 显存 | 状态 |
|------|------|------|
| RTX 3060+ 12GB | 12GB+ | 推荐 |
| RTX 40xx 16GB+ | 16GB+ | 最佳 |
| GTX 系列 <8GB | <8GB | 可能 OOM |

CPU 也可运行但极慢（一条序列数小时）。

## 安装

```bash
chmod +x *.sh scripts/*.py
./install.sh          # 基础版（仅预测）
./install.sh --full   # 完整版（含 MD 验证）
```

脚本会：
- 检测 conda / nvidia-smi
- 创建 `colabfold` 环境 (Python 3.10)
- 安装 colabfold + jax GPU 版
- `--full` 额外安装 OpenMM + PDBFixer + MDTraj
- 验证 GPU 可用

---

## 结构预测

### 从文件预测

```bash
./predict.sh example.fasta
```

FASTA 格式：
```
>蛋白质名称
氨基酸序列（单字母）
```

### 直接输入序列

```bash
./predict.sh --seq "MSKGEELFTGVV..." --name my_protein
```

### 指定参数

```bash
./predict.sh example.fasta --msa-mode single_sequence  # 快但精度稍降
./predict.sh example.fasta --num-recycle 6             # 提升精度
```

### 预测输出

`results_YYYYMMDD_HHMMSS.tar.gz`：

| 文件 | 内容 |
|------|------|
| `*_relaxed_rank_001_*.pdb` | 最优预测 3D 结构 |
| `*_plddt_*.json` | 每残基置信度 |
| `*_PAE.png` | 预测误差热力图 |
| `*_coverage.png` | 序列覆盖度图 |

---

## MD 验证（需 `--full` 安装）

在虚拟水环境中模拟蛋白质运动，评估结构是否稳定。

### 用法

```bash
# 快速检测（10ns，~5 分钟）
./validate_md.sh protein.pdb
./validate_md.sh results_1234.tar.gz

# 完整检测（50ns，~30 分钟）
./validate_md.sh protein.pdb --full --save-traj
```

### 验证输出

`validation_YYYYMMDD_HHMMSS.tar.gz`：

| 文件 | 内容 |
|------|------|
| `report.json` | MD 参数 + RMSD 汇总 + 稳定性判定 |
| `rmsd_plot.png` | RMSD 时间曲线 + ΔRMSD 波动图 |
| `*_ref.pdb` | 模拟起始构象 |
| `*_last.pdb` | 模拟结束构象 |
| `rmsd.csv` | 原始 RMSD 时间序列 |

### 稳定性判定

```
pLDDT > 85 且 RMSD < 0.35nm → ✅ PASS   (结构稳定)
pLDDT > 70 且 RMSD < 0.50nm → ⚠️ CAUTION (边缘稳定)
其他                          → ❌ WARN   (高风险)
```

---

## 全流程一键运行

```bash
# FASTA → 预测 → MD验证 → 综合报告
./validate_all.sh example.fasta --full-md

# 直接输入序列
./validate_all.sh --seq "MKFLILFN..." --name my_design --full-md
```

输出两份压缩包：`results_*.tar.gz` + `validation_*.tar.gz`

---

## 可视化

```bash
tar -xzf results_*.tar.gz
pymol results_*/*_relaxed_rank_001_*.pdb
# 或在线：https://3dmol.csb.pitt.edu
```

## 查找序列

- [UniProt](https://www.uniprot.org) — 搜蛋白质名 → Download → FASTA
- [NCBI Protein](https://www.ncbi.nlm.nih.gov/protein/) — 搜基因名

## 项目文件

```
├── install.sh          # 安装脚本（--full 含 MD）
├── predict.sh          # 结构预测
├── validate_md.sh      # MD 验证
├── validate_all.sh     # 全流程一键
├── scripts/
│   ├── run_md.py       # OpenMM MD 引擎
│   └── plot_md.py      # RMSD 绘图
├── example.fasta       # 示例序列
└── README.md
```
