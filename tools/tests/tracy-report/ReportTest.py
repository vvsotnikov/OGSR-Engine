"""The export readers must preserve quoted names and reject empty/invalid windows."""
import csv
import importlib.util
import json
import math
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

TOOLS = Path(__file__).resolve().parents[2] / 'tracy'
spec = importlib.util.spec_from_file_location('summary', TOOLS / 'Summarize-TraceStream.py')
summary = importlib.util.module_from_spec(spec)
spec.loader.exec_module(summary)


class Reports(unittest.TestCase):
    def test_quoted_names_and_complete_frames(self):
        with tempfile.TemporaryDirectory() as directory:
            prefix = str(Path(directory) / 'trace')
            name = 'scope\twith\n"quotes" and λ'
            files = {
                'frames': [('index', 'start_ns', 'duration_ns'), (0, 0, 1), (1, 1, 1),
                           (2, 2000000000, 2000000), (3, 2002000000, 5000000)],
                'zones': [('name', 'start_ns', 'duration_ns', 'thread_slot'),
                          (name, 2000000000, 2000000, 1)],
                'plots': [('name', 'time_ns', 'value'), (name, 2001000000, 12345678.125)],
            }
            for suffix, rows in files.items():
                with open(prefix + '-' + suffix + '.tsv', 'w', newline='', encoding='utf-8') as output:
                    csv.writer(output, delimiter='\t').writerows(rows)
            result = summary.summarize(prefix, 2, 3)
            self.assertEqual(result['frames']['count'], 2)
            self.assertEqual(result['frames']['meanMs'], 3.5)
            self.assertEqual(result['zonesInclusive'][0]['name'], name)
            peaks = subprocess.run([sys.executable, '-B', str(TOOLS / 'Trace-Peaks.py'), prefix, '2', '3'],
                                   capture_output=True, text=True, encoding='utf-8', check=True)
            frame = next(x for x in json.loads(peaks.stdout) if x['frame'] == 2)
            self.assertEqual(frame['inclusiveScopes'][0]['name'], name)
            self.assertEqual(frame['plotSamples'][name], [12345678.125])
            with self.assertRaisesRegex(ValueError, 'No complete frames'):
                summary.summarize(prefix, 4, 5)

    def test_invalid_windows_fail_before_reading(self):
        for start, end in [(0, math.inf), (math.nan, 1), (2, 1), (-1, 2)]:
            with self.assertRaisesRegex(ValueError, 'Invalid window'):
                summary.summarize('missing', start, end)
            peaks = subprocess.run([sys.executable, '-B', str(TOOLS / 'Trace-Peaks.py'),
                                    'missing', str(start), str(end)], capture_output=True, text=True)
            self.assertNotEqual(peaks.returncode, 0)
            self.assertIn('Invalid interval', peaks.stderr)


if __name__ == '__main__':
    unittest.main()
