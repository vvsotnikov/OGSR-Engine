"""Summarize queue-maintenance measurements within the validated cadence window."""
import argparse
import csv
import importlib.util
import json
from pathlib import Path

spec = importlib.util.spec_from_file_location('cadence', Path(__file__).with_name('Summarize-Cadence.py'))
cadence = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cadence)


def summarize(session):
    meta = json.loads((session/'session.json').read_text(encoding='utf-8-sig'))
    if not meta.get('queueBenchmark') or meta.get('traceRequested'):
        raise ValueError('Expected untraced queue benchmark')
    result = cadence.summarize(session)
    with (session/'appdata/queue-timing.csv').open(newline='', encoding='utf-8-sig') as stream:
        rows = [r for r in csv.DictReader(stream) if result['startMs'] <= int(r['game_ms']) <= result['endMs']]
    if not rows or any(int(r['compact']) != int(meta['compactQueue']) for r in rows):
        raise ValueError('Missing samples or wrong queue implementation')
    maintenance = [float(r['maintenance_us']) for r in rows]
    step = [float(r['step_us']) for r in rows]
    if any(not 0 <= a <= b for a,b in zip(maintenance, step)):
        raise ValueError('Invalid maintenance/step timing')
    removed = sum(int(r['removed']) for r in rows)
    summary = dict(session=meta['session'], engineSha256=meta['engineSha256'], compact=meta['compactQueue'],
                   extras=result['extraRequested'], seconds=result['seconds'], samples=len(rows),
                   maintenanceUs=cadence.stats(maintenance), stepUs=cadence.stats(step),
                   removed=removed, maintenanceUsPerRemoved=sum(maintenance)/removed if removed else None,
                   maintenanceMsPerSecond=sum(maintenance)/1000/result['seconds'],
                   stepMsPerSecond=sum(step)/1000/result['seconds'],
                   persistentLiving=result['persistentLivingNpcs'], zeroUpdateIds=result['zeroUpdateIds'],
                   lateMs=result['lateMs'], budgetStoppedPercent=result['budgetStoppedPercent'])
    (session/'queue-summary.json').write_text(json.dumps(summary, indent=2, allow_nan=False), encoding='utf-8')
    return summary


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('session', type=Path)
    print(json.dumps(summarize(parser.parse_args().session), indent=2, allow_nan=False))
