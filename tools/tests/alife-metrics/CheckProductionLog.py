"""Check the reader's interpretation of the production emitter fixture."""
import json
import subprocess
import sys

report = json.loads(subprocess.check_output([sys.executable, '-B', sys.argv[1], sys.argv[2]], text=True))
checks = {
    'sample count': report['sampledUpdates'] == 1,
    'spike count': len(report['loggedUpdateSpikes']) == 4,
    'suppressed count': report['suppressedSpikes'] == 2,
    'unlimited first-update budget': report['loggedUpdateSpikes'][0]['budget'] == -1,
    'sample population': report['objectsPerSample']['mean'] == 400,
    'sample total': report['sampledMilliseconds']['total']['mean'] == 2,
    'before-switch timing': report['sampledMilliseconds']['before']['mean'] == .1,
    'offline-attempt timing': report['sampledMilliseconds']['try_offline']['mean'] == .2,
    'online-attempt timing': report['sampledMilliseconds']['try_online']['mean'] == .3,
    'after-switch timing': report['sampledMilliseconds']['after']['mean'] == .4,
}
for name, passed in checks.items():
    if not passed:
        raise SystemExit('Production log round trip failed: ' + name)
