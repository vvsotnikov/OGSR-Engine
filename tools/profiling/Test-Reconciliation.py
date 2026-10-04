import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec=importlib.util.spec_from_file_location('probe',Path(__file__).with_name('Summarize-Reconciliation.py'))
probe=importlib.util.module_from_spec(spec);spec.loader.exec_module(probe)

class Evidence(unittest.TestCase):
    def test_cadence_missing_and_unsampled(self):
        with tempfile.TemporaryDirectory(prefix='ogsr-reconcile-fixture-') as directory:
            root=Path(directory);app=root/'appdata';(app/'logs').mkdir(parents=True)
            (root/'session.json').write_text(json.dumps(dict(status='regular-completed',reconcileMetrics=True,session='fixture')))
            (app/'regular-frames.csv').write_text('frame,stage\n'+''.join(f'{i+1},4\n' for i in range(1,1400)))
            log=''.join(f'[ALife reconcile] frame={i*64} pass={i*64} sampled=1 objects=10 total_ms=1 before_ms=0.2 online_dispatch_ms=0.3 offline_dispatch_ms=0.2 after_ms=0.1\n' for i in range(1,21))
            path=app/'logs/test.log';path.write_text(log)
            self.assertEqual(probe.summarize(root)['sampledPasses'],20)
            for bad, error in [(log.replace('pass=64 ', 'pass=65 '),'cadence'),
                               (log.replace('total_ms=1 ', 'total_ms=0.1 '),'stage timing'),
                               (log.replace('sampled=1 ', 'sampled=0 '),'Unsampled'),
                               (log.splitlines()[0], 'Insufficient')]:
                path.write_text(bad)
                with self.assertRaisesRegex(ValueError,error): probe.summarize(root)

if __name__=='__main__': unittest.main()
