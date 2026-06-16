#!/usr/bin/env python3
"""Plot RMSD from CSV output by run_md.py."""

import argparse
import os
import sys

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np


def parse_args():
    p = argparse.ArgumentParser(description="Plot MD RMSD trajectory")
    p.add_argument("--csv", required=True, help="RMSD CSV file from run_md.py")
    p.add_argument("--png", required=True, help="Output PNG path")
    p.add_argument("--title", default="Protein MD RMSD", help="Plot title")
    return p.parse_args()


def main():
    args = parse_args()

    if not os.path.exists(args.csv):
        print(f"[ERROR] CSV not found: {args.csv}")
        sys.exit(1)

    data = np.loadtxt(args.csv, delimiter=",", skiprows=1)
    if data.ndim == 1:
        data = data.reshape(1, -1)
    times, rmsd = data[:, 0], data[:, 1]

    fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(10, 8), gridspec_kw={"height_ratios": [3, 1]})

    ax1.plot(times, rmsd, color="#2166ac", linewidth=1.0)
    ax1.axhline(y=0.35, color="#d6604d", linestyle="--", alpha=0.6, label="0.35 nm (stable threshold)")
    ax1.axhline(y=0.50, color="#b2182b", linestyle="--", alpha=0.4, label="0.50 nm (unstable threshold)")
    ax1.set_ylabel("RMSD (nm)")
    ax1.set_title(args.title)
    ax1.legend(fontsize=8)
    ax1.grid(True, alpha=0.3)

    if len(rmsd) > 1:
        rmsd_diff = np.diff(rmsd)
        ax2.fill_between(times[1:], 0, rmsd_diff, color="#4393c3", alpha=0.5, linewidth=0)
        ax2.axhline(y=0, color="black", linewidth=0.5)
        ax2.set_xlabel("Time (ns)")
        ax2.set_ylabel("ΔRMSD (nm)")
        ax2.grid(True, alpha=0.3)

    plt.tight_layout()
    plt.savefig(args.png, dpi=150)
    print(f"[PLOT] Saved: {args.png}")


if __name__ == "__main__":
    main()
