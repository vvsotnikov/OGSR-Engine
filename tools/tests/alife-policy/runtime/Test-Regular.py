"""Reject misleading or incomplete release-driver evidence using disposable fixtures."""
import csv
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec=importlib.util.spec_from_file_location('regular', Path(__file__).with_name('Summarize-Regular.py'))
regular=importlib.util.module_from_spec(spec)
spec.loader.exec_module(regular)


def write(path, header, data):
    with path.open('w', newline='') as stream:
        writer=csv.writer(stream); writer.writerow(header.split(',')); writer.writerows(data)


class Evidence(unittest.TestCase):
    def test_complete_and_invalid_variants(self):
        with tempfile.TemporaryDirectory(prefix='ogsr-regular-fixture-') as directory:
            root=Path(directory); app=root/'appdata'; (app/'logs').mkdir(parents=True)
            (root/'session.json').write_text(json.dumps(dict(status='regular-completed', regularRequested=True,
                session='fixture', engineSha256='fixture', extraRequested=2, spawnBudgetMs=3)))
            population=[(i*1000,4,2,2,2,2,2) for i in range(30)]
            write(app/'regular-population.csv','game_ms,stage,created,retained,online,client,living',population)
            log='[regular spawn] index=1 id=10\n[regular spawn] index=2 id=11\n[regular] create_end count=2 wall_ms=4 work_ms=4 online_at_creation=0\n[regular] all_online count=2 after_create_ms=30\n'
            path=app/'logs/test.log'; path.write_text(log)
            result=regular.summarize(root)
            self.assertEqual(result['retainedOnlineClient'],2)
            meta_path=root/'session.json'
            meta=json.loads(meta_path.read_text())
            meta.update(mode='distance',distanceControl=True)
            meta_path.write_text(json.dumps(meta))
            controlled=log+'[regular control] far=2 online=1 client=1 limit=32\n'*3+'[regular control] far=2 online=0 client=0 limit=32\n'*30+'[regular] distance_control_passed\n'
            path.write_text(controlled)
            self.assertIsNone(regular.summarize(root)['retainedOnlineClient'])
            path.write_text(controlled.replace('far=2 online=0','far=2 online=1'))
            with self.assertRaisesRegex(ValueError,'violates policy'): regular.summarize(root)
            meta.update(mode='whole-map',distanceControl=False)
            meta_path.write_text(json.dumps(meta))
            path.write_text(log.replace('id=11','id=10'))
            with self.assertRaisesRegex(ValueError,'duplicate'): regular.summarize(root)
            path.write_text(log.replace('all_online count=2','all_online count=1'))
            with self.assertRaisesRegex(ValueError,'count mismatch'): regular.summarize(root)
            path.write_text(log)
            population[4]=(4000,4,2,2,2,1,2)
            write(app/'regular-population.csv','game_ms,stage,created,retained,online,client,living',population)
            with self.assertRaisesRegex(ValueError,'not fully online'): regular.summarize(root)
            population[4]=(4000,4,2,2,2,2,2)
            write(app/'regular-population.csv','game_ms,stage,created,retained,online,client,living',population)


if __name__=='__main__': unittest.main()
