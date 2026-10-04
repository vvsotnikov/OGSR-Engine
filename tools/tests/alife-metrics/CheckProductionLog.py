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
}
for name, passed in checks.items():
    if not passed:
        raise SystemExit('Production log round trip failed: ' + name)
