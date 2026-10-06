"""Check the reader's interpretation of the production emitter fixture."""
import json
import subprocess
import sys

report = json.loads(subprocess.check_output([sys.executable, '-B', sys.argv[1], sys.argv[2]], text=True))
checks = {
    'sample count': lambda: report['sampledUpdates'] == 1,
    'spike count': lambda: len(report['loggedUpdateSpikes']) == 4,
    'suppressed count': lambda: report['suppressedSpikes'] == 2,
    'unlimited first-update budget': lambda: report['loggedUpdateSpikes'][0]['budget'] == -1,
    'sample population': lambda: report['objectsPerSample']['mean'] == 400,
    'sample total': lambda: report['sampledMilliseconds']['total']['mean'] == 2,
    'before-switch timing': lambda: report['sampledMilliseconds']['before']['mean'] == .1,
    'offline-attempt timing': lambda: report['sampledMilliseconds']['try_offline']['mean'] == .2,
    'online-attempt timing': lambda: report['sampledMilliseconds']['try_online']['mean'] == .3,
    'after-switch timing': lambda: report['sampledMilliseconds']['after']['mean'] == .4,
}
for name, check in checks.items():
    if not check():
        raise SystemExit('Production log round trip failed: ' + name)
