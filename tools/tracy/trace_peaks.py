"""Show inclusive scopes overlapping the largest complete captured frames.

No causal or additive interpretation: nested scopes and parallel threads overlap.
Choose an explicit trace-time window; recursive scopes can exceed frame duration.
"""
import argparse
from trace_tsv import rows
import heapq
import json
import math
from collections import defaultdict

def peaks(prefix, start_seconds, end_seconds):
    if not (math.isfinite(start_seconds) and math.isfinite(end_seconds) and 0 <= start_seconds < end_seconds):
        raise ValueError('Invalid interval')
    selected = heapq.nlargest(8, (
        dict(index=index, start_ns=start, duration_ns=duration)
        for index, start, duration in rows(prefix, 'frames')
        if duration > 0 and start_seconds * 1e9 <= start
        and start + duration <= end_seconds * 1e9
    ), key=lambda row: row['duration_ns'])
    if not selected:
        raise ValueError('No complete frames in interval')
    first_start = min(frame['start_ns'] for frame in selected)
    last_end = max(frame['start_ns'] + frame['duration_ns'] for frame in selected)
    scopes = [defaultdict(lambda: [0, 0]) for _ in selected]
    plots = [defaultdict(list) for _ in selected]
    for plot_type, name, timestamp, value in rows(prefix, 'plots'):
        for frame, result in zip(selected, plots):
            if frame['start_ns'] <= timestamp < frame['start_ns'] + frame['duration_ns']:
                result[(plot_type, name)].append(value)
    for name, start, duration, thread, thread_name, source_id, file, line in rows(prefix, 'zones'):
        if start + duration <= first_start or start >= last_end:
            continue
        for frame, result in zip(selected, scopes):
            overlap = min(start + duration, frame['start_ns'] + frame['duration_ns']) - max(start, frame['start_ns'])
            if overlap > 0:
                value = result[(name, thread, thread_name, source_id, file, line)]
                value[0] += overlap
                value[1] = max(value[1], duration)
    output = []
    for frame, result, samples in zip(selected, scopes, plots):
        output.append(dict(frame=frame['index'], startSeconds=frame['start_ns']/1e9,
                           frameMs=frame['duration_ns']/1e6,
                           plotSamples=[dict(type=kind, name=name, values=values) for (kind, name), values in samples.items()],
                           inclusiveScopes=[dict(name=name, sourceId=source_id, file=file, line=line, threadId=thread, threadName=thread_name, overlapMs=values[0]/1e6, longestZoneMs=values[1]/1e6)
                                            for (name, thread, thread_name, source_id, file, line), values in sorted(result.items(), key=lambda entry: entry[1][0], reverse=True)[:12]]))
    return output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('prefix')
    parser.add_argument('start', type=float)
    parser.add_argument('end', type=float)
    args = parser.parse_args()
    try:
        output = peaks(args.prefix, args.start, args.end)
    except (OSError, ValueError) as error:
        parser.error(str(error))
    print(json.dumps(output, indent=2, allow_nan=False))


if __name__ == '__main__':
    main()
