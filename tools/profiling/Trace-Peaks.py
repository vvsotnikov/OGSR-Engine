"""Show inclusive scopes overlapping the largest complete captured frames.

No causal or additive interpretation: nested scopes and parallel threads overlap.
Exclude initial connection frames and choose an explicit trace-time window.
"""
import argparse
import csv
import heapq
import json
from collections import defaultdict

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('prefix')
parser.add_argument('start', type=float)
parser.add_argument('end', type=float)
args = parser.parse_args()
if not 0 <= args.start < args.end:
    raise ValueError('Invalid interval')
with open(args.prefix + '-frames.tsv', newline='') as source:
    selected = heapq.nlargest(8, (
        {key: int(value) for key, value in row.items()}
        for row in csv.DictReader(source, delimiter='\t')
        if int(row['index']) >= 2 and int(row['duration_ns']) > 0
        and args.start * 1e9 <= int(row['start_ns'])
        and int(row['start_ns']) + int(row['duration_ns']) <= args.end * 1e9
    ), key=lambda row: row['duration_ns'])
if not selected:
    raise ValueError('No complete frames in interval')
scopes = [defaultdict(lambda: [0, 0]) for _ in selected]
plots = [defaultdict(list) for _ in selected]
with open(args.prefix + '-plots.tsv', newline='') as source:
    for row in csv.DictReader(source, delimiter='\t'):
        time = int(row['time_ns'])
        for frame, result in zip(selected, plots):
            if frame['start_ns'] <= time < frame['start_ns'] + frame['duration_ns']:
                result[row['name']].append(float(row['value']))
with open(args.prefix + '-zones.tsv', newline='') as source:
    for row in csv.DictReader(source, delimiter='\t'):
        start, duration = int(row['start_ns']), int(row['duration_ns'])
        for frame, result in zip(selected, scopes):
            overlap = min(start + duration, frame['start_ns'] + frame['duration_ns']) - max(start, frame['start_ns'])
            if overlap > 0:
                value = result[(row['name'], row['thread_slot'])]
                value[0] += overlap
                value[1] = max(value[1], duration)
output = []
for frame, result, samples in zip(selected, scopes, plots):
    output.append(dict(frame=frame['index'], startSeconds=frame['start_ns']/1e9,
                       frameMs=frame['duration_ns']/1e6,
                       plotSamples=dict(samples),
                       inclusiveScopes=[dict(name=name, thread=thread, overlapMs=values[0]/1e6, longestZoneMs=values[1]/1e6)
                                        for (name, thread), values in sorted(result.items(), key=lambda entry: entry[1][0], reverse=True)[:12]]))
print(json.dumps(output, indent=2, allow_nan=False))
