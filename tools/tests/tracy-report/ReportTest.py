"""The export readers must preserve quoted names and reject empty/invalid windows."""
import json
import math
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

TOOLS = Path(__file__).resolve().parents[2] / 'tracy'
sys.path.insert(0, str(TOOLS))
import summarize_trace as summary
import trace_peaks

WRITER = os.environ.get('OGSR_TSV_WRITER')


class Reports(unittest.TestCase):
    @unittest.skipUnless(WRITER, "Set OGSR_TSV_WRITER or run this suite through CTest")
    def test_quoted_names_and_complete_frames(self):
        with tempfile.TemporaryDirectory() as directory:
            prefix = str(Path(directory) / 'trace')
            name = 'scope\twith\n"quotes" and λ'
            subprocess.run([WRITER, prefix], check=True)
            self.assertNotIn(b'\r', Path(prefix + '-zones.tsv').read_bytes())
            initial = summary.summarize(prefix, 0, .01)
            self.assertEqual(initial['frames']['count'], 2)
            self.assertEqual(len(trace_peaks.peaks(prefix, 0, .01)), 2)
            result = summary.summarize(prefix, 2, 3)
            self.assertEqual(result['frames']['count'], 2)
            self.assertEqual(result['frames']['meanMs'], 3.5)
            self.assertEqual(result['zonesInclusive'][0]['name'], name)
            self.assertEqual(len(result['zonesInclusive']), 2)
            self.assertEqual([x['file'] for x in result['zonesInclusive']], ['first.cpp', 'first.cpp'])
            self.assertEqual([x['sourceId'] for x in result['zonesInclusive']], [1, 2])
            peaks = subprocess.run([sys.executable, '-B', str(TOOLS / 'trace_peaks.py'), prefix, '2', '3'],
                                   capture_output=True, text=True, encoding='utf-8', check=True)
            frame = next(x for x in json.loads(peaks.stdout) if x['frame'] == 2)
            self.assertEqual(frame['inclusiveScopes'][0]['name'], name)
            self.assertEqual(frame['plotSamples'][name], [12345678.125])
            self.assertEqual(frame['inclusiveScopes'][0]['threadId'], 12345)
            self.assertEqual(frame['inclusiveScopes'][0]['threadName'], 'worker\t\"one\"\n')
            self.assertEqual(result['zonesInclusive'][0]['threads'][0]['id'], 12345)
            with self.assertRaisesRegex(ValueError, 'No complete frames'):
                summary.summarize(prefix, 4, 5)

    def test_invalid_windows_fail_before_reading(self):
        for start, end in [(0, math.inf), (math.nan, 1), (2, 1), (-1, 2)]:
            with self.assertRaisesRegex(ValueError, 'Invalid window'):
                summary.summarize('missing', start, end)
            peaks = subprocess.run([sys.executable, '-B', str(TOOLS / 'trace_peaks.py'),
                                    'missing', str(start), str(end)], capture_output=True, text=True)
            self.assertNotEqual(peaks.returncode, 0)
            self.assertIn('Invalid interval', peaks.stderr)
            self.assertNotIn('Traceback', peaks.stderr)


if __name__ == '__main__':
    unittest.main()
