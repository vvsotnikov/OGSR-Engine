import importlib.util
from pathlib import Path
import tempfile
import unittest
spec=importlib.util.spec_from_file_location('probe',Path(__file__).with_name('Summarize-Reconciliation.py'))
probe=importlib.util.module_from_spec(spec);spec.loader.exec_module(probe)

class Evidence(unittest.TestCase):
    def test_log_without_session_metadata(self):
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'engine.log'
            log='[ALife reconcile] frame=100 slice=64 sampled=1 objects=10 budget_ms=2 total_ms=1 before_ms=0.2 try_offline_ms=0.3 try_online_ms=0.2 after_ms=0.1\n'
            path.write_text(log)
            self.assertEqual(probe.summarize(path)['sampledSlices'],1)
            with self.assertRaisesRegex(ValueError,'No sampled'): probe.summarize(path,101)
            for bad,error in [(log.replace('slice=64','slice=65'),'cadence'),
                (log.replace('total_ms=1','total_ms=0.1'),'stage timing'),
                (log.replace('sampled=1','sampled=0'),'Unsampled'),
                (log.replace('slice=64','pass=64'),'malformed')]:
                path.write_text(bad)
                with self.assertRaisesRegex(ValueError,error): probe.summarize(path)
            path.write_text(log + log.replace('sampled=1','sampled=0').replace('slice=64','slice=65').replace('frame=100','frame=101').replace('total_ms=1','total_ms=12').replace('0.2','0').replace('0.3','0').replace('0.1','0'))
            self.assertEqual(len(probe.summarize(path)['loggedSliceSpikes']),1)

if __name__=='__main__': unittest.main()
