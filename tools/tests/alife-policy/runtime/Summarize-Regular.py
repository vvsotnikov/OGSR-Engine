"""Analyze the isolated Lua-driven Release test; no Tracy or C++ probes required."""
import argparse
import csv
import json
import re
from pathlib import Path

def rows(path):
    with path.open(newline='', encoding='utf-8-sig') as stream:
        return list(csv.DictReader(stream))


def summarize(session):
    meta = json.loads((session/'session.json').read_text(encoding='utf-8-sig'))
    if meta['status'] != 'regular-completed' or not meta.get('regularRequested'):
        raise ValueError('Expected completed regular session')
    populations = [r for r in rows(session/'appdata/regular-population.csv') if r['stage']=='4']
    count = meta['extraRequested']
    distance_mode = meta.get('mode') == 'distance'
    if len(populations) < 25 or any(int(r[key]) != count for r in populations for key in (('created','retained') if distance_mode else ('created','retained','online','client'))):
        raise ValueError('Population missing or not fully online')
    logs = list((session/'appdata/logs').glob('*.log'))
    if len(logs)!=1: raise ValueError('Ambiguous engine log')
    log = logs[0].read_text(encoding='utf-8', errors='replace')
    creation = re.search(r'\[regular\] create_end count=(\d+) wall_ms=([\d.]+) work_ms=([\d.]+) online_at_creation=(\d+)', log)
    online = re.search(r'\[regular\] all_online count=(\d+) after_create_ms=([\d.]+)', log)
    ids = re.findall(r'\[regular spawn\] index=\d+ id=(\d+)', log)
    if not creation or (not distance_mode and not online) or len(ids)!=count or len(set(ids))!=count:
        raise ValueError('Incomplete or duplicate creation evidence')
    if int(creation[1]) != count or (online and int(online[1]) != count):
        raise ValueError('Log population count mismatch')
    if meta.get('distanceControl') and count:
        controls = re.findall(r'\[regular control\] far=(\d+) online=(\d+) client=(\d+) limit=([\d.]+)', log)
        if len(controls) < 25 or '[regular] distance_control_passed' not in log:
            raise ValueError('Missing distant control evidence')
        for far, active, client, limit in controls[-25:]:
            expected = 0 if distance_mode else int(far)
            if int(far) <= 0 or float(limit) <= 0 or int(active) != expected or int(client) != expected:
                raise ValueError('Distant control violates policy')
    result = dict(session=meta['session'], engineSha256=meta['engineSha256'], extras=count,
                  verifiedIds=len(meta.get('verifyIds', [])), samples=len(populations),
                  allOnlineAfterCreateMs=float(online[2]) if online else None,
                  retainedOnlineClient=None if distance_mode else count,
                  onlineMin=min(int(r['online']) for r in populations),
                  onlineMax=max(int(r['online']) for r in populations))
    (session/'regular-summary.json').write_text(json.dumps(result, indent=2, allow_nan=False), encoding='utf-8')
    return result


if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('session', type=Path)
    print(json.dumps(summarize(parser.parse_args().session), indent=2, allow_nan=False))
