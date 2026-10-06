"""The export readers must preserve quoted names and reject empty/invalid windows."""
import json
import csv
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
import trace_tsv

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
            self.assertEqual(next(p['values'] for p in frame['plotSamples'] if p['name'] == name), [12345678.125])
            self.assertEqual(len([p for p in frame['plotSamples'] if p['name'] == 'CPU usage']), 2)
            crossing = next(z for z in frame['inclusiveScopes'] if z['name'] == 'crossing')
            self.assertEqual(crossing['overlapMs'], .5)
            self.assertEqual(crossing['file'].encode('utf-8', errors='surrogateescape'), b'path-\xff.cpp')
            self.assertNotIn('crossing', [z['name'] for z in result['zonesInclusive']])
            self.assertEqual(len([z for z in frame['inclusiveScopes'] if z['sourceId'] == 1]), 2)
            self.assertEqual(frame['inclusiveScopes'][0]['threadId'], 12345)
            self.assertEqual(frame['inclusiveScopes'][0]['threadName'], 'worker\t\"one\"\n')
            self.assertEqual(result['zonesInclusive'][0]['threads'][0]['id'], 12345)
            with self.assertRaisesRegex(ValueError, 'No complete frames'):
                summary.summarize(prefix, 4, 5)

    @unittest.skipUnless(WRITER, "Run through CTest")
    def test_invalid_tsv(self):
        with tempfile.TemporaryDirectory() as directory:
            prefix = str(Path(directory) / 'trace')
            for suffix in ['frames', 'zones', 'plots']:
                for content in [b'', b'wrong\theader\n']:
                    subprocess.run([WRITER, prefix], check=True)
                    Path(prefix + '-' + suffix + '.tsv').write_bytes(content)
                    scripts = ['trace_peaks.py'] if suffix == 'plots' else ['summarize_trace.py', 'trace_peaks.py']
                    for script in scripts:
                        result = subprocess.run([sys.executable, '-B', str(TOOLS / script), prefix, '2', '3'], capture_output=True, text=True)
                        self.assertNotEqual(result.returncode, 0)
                        self.assertIn('schema', result.stderr)
                        self.assertNotIn('Traceback', result.stderr)

    def test_invalid_windows_fail_before_reading(self):
        for start, end in [(0, math.inf), (math.nan, 1), (2, 1), (-1, 2)]:
            with self.assertRaisesRegex(ValueError, 'Invalid window'):
                summary.summarize('missing', start, end)
            peaks = subprocess.run([sys.executable, '-B', str(TOOLS / 'trace_peaks.py'),
                                    'missing', str(start), str(end)], capture_output=True, text=True)
            self.assertNotEqual(peaks.returncode, 0)
            self.assertIn('Invalid interval', peaks.stderr)
            self.assertNotIn('Traceback', peaks.stderr)

    def test_numeric_errors_identify_file_column_and_line(self):
        with tempfile.TemporaryDirectory() as directory:
            prefix = str(Path(directory) / 'trace')
            valid = {
                'frames': ['1', '2000000000', '1000000'],
                'zones': ['scope\nname', '2000000000', '1000000', '7', 'worker', '1', 'a.cpp', '12'],
                'plots': ['user', 'load', '2000000000', '1.5'],
            }
            for kind, converters in trace_tsv.CONVERTERS.items():
                for column, convert in enumerate(converters):
                    if convert is str:
                        continue
                    for invalid in (['bad', 'nan', 'inf'] if convert is float else ['bad']):
                        with self.subTest(kind=kind, column=column, invalid=invalid):
                            for file_kind, values in valid.items():
                                row = values.copy()
                                if file_kind == kind:
                                    row[column] = invalid
                                with open(prefix + '-' + file_kind + '.tsv', 'w', newline='', encoding='utf-8') as stream:
                                    writer = csv.writer(stream, delimiter='\t')
                                    writer.writerow(trace_tsv.HEADERS[file_kind])
                                    writer.writerow(row)
                            scripts = ['trace_peaks.py'] if kind == 'plots' else ['summarize_trace.py', 'trace_peaks.py']
                            for script in scripts:
                                result = subprocess.run([sys.executable, '-B', str(TOOLS / script), prefix, '2', '3'], capture_output=True, text=True)
                                self.assertNotEqual(result.returncode, 0)
                                self.assertIn(prefix + '-' + kind + '.tsv', result.stderr)
                                self.assertIn('invalid ' + trace_tsv.HEADERS[kind][column], result.stderr)
                                self.assertIn('line 3' if kind == 'zones' else 'line 2', result.stderr)
                                self.assertNotIn('Traceback', result.stderr)


if __name__ == '__main__':
    unittest.main()
