"""Summarize opt-in sampled reconciliation timings, aligned to driver frames.

Unsampled substage zeros are placeholders, never measurements. Overall traversal
logs exist only on sampled passes or when duration is at least 10 ms.
"""
import argparse
import csv
import json
import math
import re
from pathlib import Path

pattern = re.compile(r'\[ALife reconcile\] frame=(\d+) pass=(\d+) sampled=([01]) objects=(\d+) total_ms=([\d.]+) before_ms=([\d.]+) online_dispatch_ms=([\d.]+) offline_dispatch_ms=([\d.]+) after_ms=([\d.]+)')
names = ['frame', 'pass', 'sampled', 'objects', 'total', 'before', 'online_dispatch', 'offline_dispatch', 'after']

def stats(values):
    if not values:
        raise ValueError('No samples')
    ordered = sorted(values)
    return dict(count=len(values), mean=math.fsum(values)/len(values), p95=ordered[math.ceil(len(values)*.95)-1], max=ordered[-1])

def summarize(session):
    meta = json.loads((session/'session.json').read_text(encoding='utf-8-sig'))
    if meta['status'] != 'regular-completed' or not meta.get('reconcileMetrics') or meta.get('traceRequested'):
        raise ValueError('Expected completed untraced reconciliation session')
    with (session/'appdata/regular-frames.csv').open(newline='') as f:
        # Row F measures the callback interval ending at F, so associate the
        # stage with F-1, which contained the worker traversal.
        measured = {int(r['frame'])-1 for r in csv.DictReader(f) if r['stage']=='4'}
    logs = list((session/'appdata/logs').glob('*.log'))
    if len(logs) != 1: raise ValueError('Ambiguous log')
    samples, spikes = [], []
    for match in pattern.finditer(logs[0].read_text(encoding='utf-8', errors='replace')):
        row = dict(zip(names, [int(v) if i<4 else float(v) for i,v in enumerate(match.groups())]))
        if row['sampled']:
            if row['pass'] % 64 != 0 or row['objects'] <= 0:
                raise ValueError('Invalid sample cadence or count')
            if sum(row[key] for key in names[5:]) > row['total'] + .05:
                raise ValueError('Nonexclusive or invalid stage timing')
            if row['frame'] in measured: samples.append(row)
        elif any(row[key] for key in names[5:]) or row['objects']:
            raise ValueError('Unsampled stages must not contain timings')
        if row['total'] >= 10: spikes.append(dict(row, inMeasurementWindow=row['frame'] in measured))
    if len(samples) < 20: raise ValueError('Insufficient steady-state stage samples')
    result = dict(session=meta['session'], sampledPasses=len(samples), measuredFrames=len(measured),
                  objectsPerSample=stats([r['objects'] for r in samples]),
                  sampledMilliseconds={key:stats([r[key] for r in samples]) for key in names[4:]},
                  allSessionTraversalSpikes=spikes,
                  caveat='Stage sampling every 64 passes; dispatch includes virtual maintenance and transitions. Timer/log overhead is not subtracted. No unsampled mean is available.')
    (session/'reconciliation-summary.json').write_text(json.dumps(result,indent=2,allow_nan=False))
    return result

if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('session',type=Path)
    print(json.dumps(summarize(parser.parse_args().session),indent=2,allow_nan=False))
