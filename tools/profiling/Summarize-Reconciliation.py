"""Summarize reconciliation updates from an engine log, optionally by frame range.

Unsampled stage zeros are placeholders. Only sampled updates and rate-limited
spikes are logged; suppressed counts span the interval preceding each record.
"""
import argparse
import json
import math
import re
from pathlib import Path

pattern = re.compile(
    r'\[ALife reconcile\] frame=(\d+) update=(\d+) sampled=([01]) spike=([01]) '
    r'suppressed=(\d+) objects=(\d+) budget_ms=(-?\d+(?:\.\d+)?) total_ms=(\d+(?:\.\d+)?) '
    r'before_ms=(\d+(?:\.\d+)?) try_offline_ms=(\d+(?:\.\d+)?) try_online_ms=(\d+(?:\.\d+)?) after_ms=(\d+(?:\.\d+)?)\s*$'
)
names = ['frame', 'update', 'sampled', 'spike', 'suppressed', 'objects',
         'budget', 'total', 'before', 'try_offline', 'try_online', 'after']
stages = names[8:]


def stats(values):
    if not values:
        return None
    ordered = sorted(values)
    return dict(count=len(values), mean=math.fsum(values) / len(values),
                p95=ordered[math.ceil(len(values) * .95) - 1], max=ordered[-1])


def summarize(log_path, first_frame=0, last_frame=None, skip_malformed=False):
    samples, spikes = [], []
    suppressed = 0
    malformed = 0
    for line in log_path.read_text(encoding='utf-8', errors='replace').splitlines():
        if '[ALife reconcile]' not in line:
            continue
        match = pattern.search(line)
        if not match:
            if skip_malformed:
                malformed += 1
                continue
            raise ValueError('Unsupported or malformed reconciliation line')
        row = dict(zip(names, [int(v) if i < 6 else float(v)
                              for i, v in enumerate(match.groups())]))
        if row['frame'] < first_frame or (last_frame is not None and row['frame'] > last_frame):
            continue
        suppressed += row['suppressed']
        if row['sampled']:
            if sum(row[key] for key in stages) > row['total'] + .05:
                raise ValueError('Nonexclusive or invalid stage timing')
            samples.append(row)
        elif any(row[key] for key in stages):
            raise ValueError('Unsampled stages must not contain timings')
        if row['spike']:
            spikes.append(row)
    if not samples and not spikes:
        raise ValueError('No reconciliation records in requested range')
    return dict(
        sampledUpdates=len(samples), frameRange=[first_frame, last_frame],
        suppressedSpikes=suppressed, malformedLines=malformed,
        objectsPerSample=stats([r['objects'] for r in samples]),
        sampledMilliseconds={key: stats([r[key] for r in samples]) for key in names[7:]},
        loggedUpdateSpikes=spikes,
        caveat=(
            'Records cover update_switch invocations, not necessarily full traversals. '
            'The budget is the effective iterator limit; -1 means unlimited. '
            'Budget-exhausting slices tend toward that limit plus overshoot; compare '
            'visits and stage shares alongside elapsed totals, not totals alone. '
            'Stage timers consume the budget and can reduce sampled visits; '
            'objectsPerSample is not normal unsampled throughput. '
            'Neither visit/population ratios nor update counters measure per-object latency. '
            'Spikes can include work, waits and preemption; they do not identify a slow object. '
            'Suppressed counts cover preceding reporting intervals, which may straddle '
            'frame limits; an unreported final interval is absent. Malformed lines are counted '
            'across the whole log. Logging and population '
            'inventory add cost outside these totals. No unsampled mean is available.'
        ),
    )


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('log', type=Path)
    parser.add_argument('--first-frame', type=int, default=0)
    parser.add_argument('--last-frame', type=int)
    parser.add_argument('--skip-malformed', action='store_true',
                        help='Skip and count unparseable records, for truncated crash logs')
    args = parser.parse_args()
    print(json.dumps(summarize(args.log, args.first_frame, args.last_frame, args.skip_malformed), indent=2, allow_nan=False))
