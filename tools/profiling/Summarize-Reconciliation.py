"""Summarize reconciliation slices from an engine log, optionally by frame range.

No session manifest or archived launcher is required. Unsampled stage zeros are
placeholders. Only sampled slices and slices lasting >=10 ms are logged.
"""
import argparse
import json
import math
import re
from pathlib import Path

pattern = re.compile(r'\[ALife reconcile\] frame=(\d+) slice=(\d+) sampled=([01]) objects=(\d+) budget_ms=(-?[\d.]+) total_ms=([\d.]+) before_ms=([\d.]+) try_offline_ms=([\d.]+) try_online_ms=([\d.]+) after_ms=([\d.]+)')
names = ['frame', 'slice', 'sampled', 'objects', 'budget', 'total', 'before', 'try_offline', 'try_online', 'after']
stages = names[6:]

def stats(values):
    if not values: return None
    ordered = sorted(values)
    return dict(count=len(values), mean=math.fsum(values)/len(values), p95=ordered[math.ceil(len(values)*.95)-1], max=ordered[-1])

def summarize(log_path, first_frame=0, last_frame=None):
    samples, spikes = [], []
    for line in log_path.read_text(encoding='utf-8', errors='replace').splitlines():
        if '[ALife reconcile]' not in line: continue
        match = pattern.search(line)
        if not match: raise ValueError('Unsupported or malformed reconciliation line')
        row = dict(zip(names, [int(v) if i<4 else float(v) for i,v in enumerate(match.groups())]))
        if row['frame'] < first_frame or (last_frame is not None and row['frame'] > last_frame): continue
        if row['sampled']:
            if row['slice'] % 64 != 0: raise ValueError('Invalid sample cadence')
            if sum(row[key] for key in stages) > row['total'] + .05:
                raise ValueError('Nonexclusive or invalid stage timing')
            samples.append(row)
        elif any(row[key] for key in stages):
            raise ValueError('Unsampled stages must not contain timings')
        if row['total'] >= 10: spikes.append(row)
    if not samples: raise ValueError('No sampled slices in requested range')
    return dict(sampledSlices=len(samples), frameRange=[first_frame,last_frame],
        objectsPerSample=stats([r['objects'] for r in samples]),
        sampledMilliseconds={key:stats([r[key] for r in samples]) for key in names[5:]},
        loggedSliceSpikes=spikes,
        caveat='Samples are cursor slices, not full-population traversals. Timer overhead consumes the slice budget. Logging and population inventory add cost outside these stage totals. No unsampled mean is available; budget=-1 means unlimited.')

if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('log',type=Path)
    parser.add_argument('--first-frame',type=int,default=0)
    parser.add_argument('--last-frame',type=int)
    args=parser.parse_args()
    print(json.dumps(summarize(args.log,args.first_frame,args.last_frame),indent=2,allow_nan=False))
