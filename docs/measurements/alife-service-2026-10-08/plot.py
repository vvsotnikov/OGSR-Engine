"""Render the published nearest-rank frame quantiles; requires matplotlib."""
from pathlib import Path
import csv
import math
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

root = Path(__file__).resolve().parent
rows = list(csv.DictReader((root / 'frame-quantiles.csv').open()))
fig, axes = plt.subplots(1, 2, figsize=(10, 4), sharey=True)
for ax, policy, title in zip(axes, ('distance', 'whole'), ('Distance: 59-62 online', 'Whole-map: 400 online')):
    for repeat in (1, 2):
        for enabled, color in (('off', '#306baf'), ('on', '#c15426')):
            run = f'r{repeat}-{policy}-{enabled}'
            data = [r for r in rows if r['run'] == run and float(r['percentile']) >= 50]
            ax.plot([float(r['percentile']) for r in data], [float(r['wall_ms']) for r in data],
                    color=color, linestyle='-' if repeat == 1 else '--', linewidth=1.5,
                    label=f'Trace {enabled}, run {repeat}')
    ax.set_title(title)
    ax.set_xlabel('Percentile (100 = observed maximum)')
    ax.set_xlim(50, 100)
    ax.set_ylim(0, math.ceil(max(float(r["wall_ms"]) for r in rows) / 5) * 5)
    ax.grid(alpha=.25)
axes[0].set_ylabel('Frame interval (ms)')
axes[0].legend(fontsize=8)
fig.suptitle('Bar + 400 characters: warmed 45-second windows, Release')
fig.tight_layout()
fig.savefig(root / 'frame-distribution.png', dpi=160)
