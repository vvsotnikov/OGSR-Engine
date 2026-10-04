"""Summarize CPU trace TSV output; retain durations in the selected window."""
import argparse
import csv
from array import array
from collections import defaultdict
import json
import math


def statistics(values):
    ordered = sorted(values)
    if not ordered:
        return None
    count = len(ordered)
    total = math.fsum(ordered)
    return dict(count=count, totalMs=total, meanMs=total / count,
                medianMs=ordered[math.ceil(count * .5) - 1],
                p95Ms=ordered[math.ceil(count * .95) - 1],
                p99Ms=ordered[math.ceil(count * .99) - 1], maxMs=ordered[-1])


def summarize(prefix, start, end):
    if not (math.isfinite(start) and math.isfinite(end) and 0 <= start < end):
        raise ValueError("Invalid window")
    lower, upper = start * 1e9, end * 1e9
    frames = array('d')
    with open(prefix + '-frames.tsv', encoding='utf-8') as stream:
        if next(stream).strip() != 'index\tstart_ns\tduration_ns':
            raise ValueError('Unexpected frame schema')
        for line in stream:
            index, timestamp, duration = map(int, line.split('\t'))
            if duration > 0 and timestamp >= lower and timestamp + duration <= upper:
                frames.append(duration / 1e6)
    if not frames:
        raise ValueError('No complete frames in selected window')
    zones = defaultdict(lambda: array('d'))
    threads = defaultdict(set)
    with open(prefix + '-zones.tsv', encoding='utf-8', newline='') as stream:
        reader = csv.reader(stream, delimiter='\t')
        if next(reader) != ['name', 'start_ns', 'duration_ns', 'thread_id', 'thread_name']:
            raise ValueError('Unexpected zone schema')
        for name, timestamp, duration, thread, thread_name in reader:
            timestamp, duration = int(timestamp), int(duration)
            if duration >= 0 and timestamp >= lower and timestamp + duration <= upper:
                zones[name].append(duration / 1e6)
                threads[name].add((int(thread), thread_name))
    return dict(startSeconds=start, endSeconds=end,
                selection='Complete events in window. Inclusive and parallel zone times are not additive.',
                percentileMethod='nearest rank', frames=statistics(frames),
                zonesInclusive=[dict(name=name, timing=statistics(values), threads=[dict(id=tid, name=tname) for tid, tname in sorted(threads[name])])
                                for name, values in sorted(zones.items(), key=lambda item: math.fsum(item[1]), reverse=True)])


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('prefix')
    parser.add_argument('start', type=float)
    parser.add_argument('end', type=float)
    args = parser.parse_args()
    try:
        result = summarize(args.prefix, args.start, args.end)
    except (OSError, ValueError) as error:
        parser.error(str(error))
    with open(args.prefix + '-summary.json', 'w', encoding='utf-8') as stream:
        json.dump(result, stream, indent=2, allow_nan=False)
    print(json.dumps(result['frames']))
