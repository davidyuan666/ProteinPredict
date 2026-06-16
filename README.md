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
chmod +x install.sh predict.sh
./install.sh
```

脚本会：
- 检测 conda / nvidia-smi
- 创建 `colabfold` 环境 (Python 3.10)
- 安装 colabfold + jax GPU 版
- 验证 GPU 可用

## 使用

### 1. 从文件预测

```bash
./predict.sh example.fasta
```

FASTA 格式：
```
>蛋白质名称
氨基酸序列（单字母）
```

### 2. 直接输入序列

```bash
./predict.sh --seq "MSKGEELFTGVV..." --name my_protein
```

### 3. 批量预测

```bash
./predict.sh --multi batch.fasta
```

### 4. 指定参数

```bash
# 纯序列模式（不做 MSA 搜索，快但精度稍降）
./predict.sh example.fasta --msa-mode single_sequence

# 增加回收轮数（提高精度，更慢）
./predict.sh example.fasta --num-recycle 6
```

## 输出

运行后在当前目录生成 `results_YYYYMMDD_HHMMSS.tar.gz`，包含：

| 文件 | 内容 |
|------|------|
| `*_relaxed_rank_001_*.pdb` | 最优预测 3D 结构 |
| `*_plddt_*.json` | 每残基置信度 |
| `*_PAE.png` | 预测误差热力图 |
| `*_coverage.png` | 序列覆盖度图 |

## 可视化

```bash
# 解压
tar -xzf results_*.tar.gz

# PyMOL 查看
pymol results_*/*_relaxed_rank_001_*.pdb

# 或在线查看：https://3dmol.csb.pitt.edu
```

## 查找序列

- [UniProt](https://www.uniprot.org) — 搜蛋白质名 → Download → FASTA
- [NCBI Protein](https://www.ncbi.nlm.nih.gov/protein/) — 搜基因名
