import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('probe', Path(__file__).with_name('Summarize-Reconciliation.py'))
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)
SAMPLE = ('[ALife reconcile] frame=100 update=64 sampled=1 spike=0 suppressed=2 objects=10 '
          'budget_ms=300000.000000 total_ms=1 before_ms=0.2 try_offline_ms=0.3 '
          'try_online_ms=0.2 after_ms=0.1\n')
SPIKE = ('[ALife reconcile] frame=101 update=65 sampled=0 spike=1 suppressed=3 objects=12 '
         'budget_ms=300000.000000 total_ms=12 before_ms=0 try_offline_ms=0 '
         'try_online_ms=0 after_ms=0\n')


class Evidence(unittest.TestCase):
    def summarize(self, text, *frames):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'engine.log'
            path.write_text(text)
            return probe.summarize(path, *frames)

    def test_samples_and_reporting_intervals(self):
        result = self.summarize(SAMPLE + SPIKE)
        self.assertEqual(result['sampledUpdates'], 1)
        self.assertEqual(result['suppressedSpikes'], 5)
        self.assertEqual(len(result['loggedUpdateSpikes']), 1)

    def test_spike_only_and_empty_windows(self):
        result = self.summarize(SAMPLE + SPIKE, 101)
        self.assertEqual(result['sampledUpdates'], 0)
        self.assertEqual(result['suppressedSpikes'], 3)
        with self.assertRaisesRegex(ValueError, 'No reconciliation'):
            self.summarize(SAMPLE, 101)

    def test_invalid_stages_and_format(self):
        for bad, error in [
            (SAMPLE.replace('total_ms=1 ', 'total_ms=0.1 '), 'stage timing'),
            (SAMPLE.replace('sampled=1', 'sampled=0'), 'Unsampled'),
            (SAMPLE.replace('update=64', 'pass=64'), 'malformed'),
        ]:
            with self.subTest(error=error), self.assertRaisesRegex(ValueError, error):
                self.summarize(bad)


if __name__ == '__main__':
    unittest.main()
