"""Analyze per-stalker scheduler dispatches, including NPCs with no dispatches."""
import argparse
import csv
import json
import math
from collections import defaultdict
from pathlib import Path
import re


def stats(values):
    data = sorted(values)
    if not data:
        return None
    return dict(count=len(data), mean=sum(data)/len(data), median=data[math.ceil(len(data)*.5)-1],
                p95=data[math.ceil(len(data)*.95)-1], p99=data[math.ceil(len(data)*.99)-1], max=data[-1])


def rows(path):
    with path.open(encoding='utf-8-sig', newline='') as stream:
        yield from csv.DictReader(stream)


def summarize(session):
    meta = json.loads((session/'session.json').read_text(encoding='utf-8-sig'))
    if meta['status'] != 'stress-completed' or not meta.get('cadenceRequested'):
        raise ValueError('Incomplete or non-cadence session')
    log_paths = list((session/'appdata/logs').glob('*.log'))
    if len(log_paths) != 1:
        raise ValueError('Ambiguous engine log')
    log = log_paths[0].read_text(encoding='utf-8', errors='replace')
    spawned = [int(value) for value in re.findall(r'\[stress spawn\] id=(\d+)', log)]
    combat_start_match = re.search(r'\[cadence combat\] begin game_ms=(\d+) fighters=(\d+)', log)
    combat_start = int(combat_start_match[1]) if combat_start_match else None
    first_enemy = {}
    batches = defaultdict(dict)
    for row in rows(session/'appdata/cadence-cohort.csv'):
        if row['stage'] == '3':
            time, npc = int(row['game_ms']), int(row['id'])
            if npc in batches[time]:
                raise ValueError('Duplicate ID in cohort sample')
            batches[time][npc] = row
    times = sorted(batches)
    if len(times) < 20:
        raise ValueError('Insufficient cohort coverage')
    start, end = times[0], times[-1]
    duration = (end-start)/1000
    if duration < 25:
        raise ValueError('Cohort window too short')
    persistent = set.intersection(*[{npc for npc, row in batches[t].items() if row['alive'] == '1'} for t in times])
    if not persistent:
        raise ValueError('No continuously observed living NPCs')
    events = defaultdict(list)
    for row in rows(session/'appdata/cadence-updates.csv'):
        if row['context_valid'] != '1':
            raise ValueError('Stalker callback lacks matching scheduler context')
        time = int(row['dispatch_ms'])
        if combat_start is not None and time >= combat_start and int(row['id']) in spawned and int(row['enemy']) in spawned:
            first_enemy.setdefault(int(row['id']), time-combat_start)
        if start <= time <= end:
            npc = int(row['id'])
            if row['realtime'] != '0':
                raise ValueError('Unexpected realtime stalker; analyze separately')
            events[npc].append({key: int(value) for key, value in row.items()})
    details = []
    intervals, lateness, requested = [], [], []
    for npc in sorted(persistent):
        values = events[npc]
        dispatch = [v['dispatch_ms'] for v in values]
        gaps = [b-a for a,b in zip(dispatch, dispatch[1:])]
        if any(gap < 0 for gap in gaps):
            raise ValueError('Non-monotonic dispatch clock')
        late = [v['late_ms'] for v in values]
        wanted = [v['requested_ms'] for v in values]
        intervals.extend(gaps)
        lateness.extend(late)
        requested.extend(wanted)
        details.append(dict(id=npc, spawnIndex=spawned.index(npc) if npc in spawned else None,
                            updates=len(values), updatesPerSecond=len(values)/duration,
                            actualIntervalMs=stats(gaps), requestedIntervalMs=stats(wanted), lateMs=stats(late),
                            maxSilentGapMs=max(gaps+[dispatch[0]-start, end-dispatch[-1]]) if dispatch else end-start))
    scheduler = [r for r in rows(session/'appdata/cadence-scheduler.csv') if start <= int(r['game_ms']) <= end]
    if not scheduler:
        raise ValueError('Missing scheduler samples')
    shots_path = session/'appdata/cadence-shots.csv'
    shots = [r for r in rows(shots_path) if start <= int(r['game_ms']) <= end and int(r['owner']) in spawned] if shots_path.exists() else []
    enemy_updates = sum(v['enemy'] in spawned for npc in spawned for v in events[npc])
    combat = dict(configured=bool(combat_start_match), spawnedShots=len(shots),
                  spawnedShooters=len({r['owner'] for r in shots}), enemySelectionUpdates=enemy_updates,
                  firstObservedEnemyMs=stats(list(first_enemy.values())), npcFirstEnemyMs=first_enemy,
                  spawnedLivingFirst=sum(npc in batches[start] and batches[start][npc]['alive']=='1' for npc in spawned),
                  spawnedLivingLast=sum(npc in batches[end] and batches[end][npc]['alive']=='1' for npc in spawned))
    combat['engagementConfirmed'] = bool(combat_start_match and shots and enemy_updates)
    combat['spawnedAliveDispatchLateMs'] = stats([v['late_ms'] for npc in spawned for v in events[npc] if v['alive']])
    result = dict(session=meta['session'], scenario=meta.get('scenario'), extraRequested=meta['requestedExtraStalkers'],
                  startMs=start, endMs=end, seconds=duration, cohortSamples=len(times), persistentLivingNpcs=len(persistent),
                  persistentSpawnedNpcs=len(persistent.intersection(spawned)), zeroUpdateIds=[d['id'] for d in details if d['updates']==0],
                  actualIntervalMs=stats(intervals), requestedIntervalMs=stats(requested), lateMs=stats(lateness),
                  allAliveDispatchLateMs=stats([v['late_ms'] for values in events.values() for v in values if v['alive']]),
                  lateOver50ms=sum(v > 50 for v in lateness), lateOver100ms=sum(v > 100 for v in lateness),
                  npcP95LateMs=stats([d['lateMs']['p95'] for d in details if d['lateMs']]),
                  npcUpdateRates=stats([d['updatesPerSecond'] for d in details]),
                  npcMaxSilentGapMs=stats([d['maxSilentGapMs'] for d in details]),
                  budgetStoppedPercent=100*sum(r['budget_stopped']=='1' for r in scheduler)/len(scheduler),
                  remainingDueObjects=stats([int(r['overdue']) for r in scheduler]),
                  remainingQueueMaxLateMs=max(int(r['max_late_ms']) for r in scheduler), combat=combat)
    (session/'cadence-npcs.json').write_text(json.dumps(details, indent=2, allow_nan=False), encoding='utf-8')
    (session/'cadence-summary.json').write_text(json.dumps(result, indent=2, allow_nan=False), encoding='utf-8')
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('session', type=Path)
    args = parser.parse_args()
    print(json.dumps(summarize(args.session), indent=2, allow_nan=False))
