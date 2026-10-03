"""Analyze the isolated Lua-driven Release test; no Tracy or C++ probes required."""
import argparse
import csv
import importlib.util
import json
import re
from pathlib import Path

spec = importlib.util.spec_from_file_location('cadence', Path(__file__).with_name('Summarize-Cadence.py'))
cadence = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cadence)


def rows(path):
    with path.open(newline='', encoding='utf-8-sig') as stream:
        return list(csv.DictReader(stream))


def summarize(session):
    meta = json.loads((session/'session.json').read_text(encoding='utf-8-sig'))
    if meta['status'] != 'regular-completed' or not meta.get('regularRequested'):
        raise ValueError('Expected completed regular session')
    frames = rows(session/'appdata/regular-frames.csv')
    measured = [r for r in frames if r['stage'] == '4']
    warmup = [float(r['frame_ms']) for r in frames if r['stage'] in ('2','3')]
    times = [float(r['frame_ms']) for r in measured]
    if (not times or not 28 <= sum(times)/1000 <= 32 or any(int(r['frame_gap']) != 1 for r in measured)
            or any(int(b['frame'])-int(a['frame']) != 1 for a,b in zip(measured, measured[1:]))):
        raise ValueError('Missing frames or incomplete window')
    if any(not 0 < float(r['frame_ms']) < 10000 for r in frames):
        raise ValueError('Invalid frame clock')
    populations = [r for r in rows(session/'appdata/regular-population.csv') if r['stage']=='4']
    count = meta['extraRequested']
    if len(populations) < 25 or any(int(r[key]) != count for r in populations for key in ('created','retained','online','client')):
        raise ValueError('Population missing or not fully online')
    batches = rows(session/'appdata/regular-batches.csv')
    creation_frames = {int(r['frame']) for r in batches if int(r['count']) > 0}
    # Callback interval F includes work done after callback F-1. The last
    # creation batch can therefore be labelled stage 3; exclude it explicitly.
    post_creation = [float(r['frame_ms']) for r in frames if r['stage']=='3' and int(r['frame'])-1 not in creation_frames]
    if sum(int(r['count']) for r in batches) != count:
        raise ValueError('Creation count mismatch')
    if meta['spawnBudgetMs'] and any(int(r['count']) > 8 for r in batches):
        raise ValueError('Batch count cap exceeded')
    logs = list((session/'appdata/logs').glob('*.log'))
    if len(logs)!=1: raise ValueError('Ambiguous engine log')
    log = logs[0].read_text(encoding='utf-8', errors='replace')
    creation = re.search(r'\[regular\] create_end count=(\d+) wall_ms=([\d.]+) work_ms=([\d.]+) online_at_creation=(\d+)', log)
    online = re.search(r'\[regular\] all_online count=(\d+) after_create_ms=([\d.]+)', log)
    ids = re.findall(r'\[regular spawn\] index=\d+ id=(\d+)', log)
    if not creation or not online or len(ids)!=count or len(set(ids))!=count:
        raise ValueError('Incomplete or duplicate creation evidence')
    if int(creation[1]) != count or int(online[1]) != count:
        raise ValueError('Log population count mismatch')
    result = dict(session=meta['session'], engineSha256=meta['engineSha256'], extras=count,
                  activationQueue=meta.get('activationQueue', False), traceRequested=meta.get('traceRequested', False),
                  savePendingRequested=meta.get('savePendingRequested', False), verifiedIds=len(meta.get('verifyIds', [])),
                  compact=meta['compactQueue'], budgetMs=meta['spawnBudgetMs'], frameMs=cadence.stats(times),
                  seconds=sum(times)/1000, creationWarmupMaxFrameMs=max(warmup),
                  postCreationMaxFrameMs=max(post_creation),
                  creationWallMs=float(creation[2]), creationWorkMs=float(creation[3]),
                  onlineAtCreation=int(creation[4]), allOnlineAfterCreateMs=float(online[2]),
                  batches=len(batches), batchWorkMs=cadence.stats([float(r['work_ms']) for r in batches]),
                  maxBatchCount=max(int(r['count']) for r in batches),
                  livingMin=min(int(r['living']) for r in populations), livingMax=max(int(r['living']) for r in populations),
                  retainedOnlineClient=count, over33ms=sum(t>1000/30 for t in times))
    (session/'regular-summary.json').write_text(json.dumps(result, indent=2, allow_nan=False), encoding='utf-8')
    return result


if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('session', type=Path)
    print(json.dumps(summarize(parser.parse_args().session), indent=2, allow_nan=False))
