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
                session='fixture', engineSha256='fixture', extraRequested=2, compactQueue=True, spawnBudgetMs=3)))
            frame_rows=[(0,0,3,10,1),(1,1,3,200,1)]+[(i,i*1000,4,1000,1) for i in range(2,32)]
            write(app/'regular-frames.csv','frame,game_ms,stage,frame_ms,frame_gap',frame_rows)
            population=[(i*1000,4,2,2,2,2,2) for i in range(30)]
            write(app/'regular-population.csv','game_ms,stage,created,retained,online,client,living',population)
            write(app/'regular-batches.csv','frame,count,work_ms',[(0,2,4)])
            log='[regular spawn] index=1 id=10\n[regular spawn] index=2 id=11\n[regular] create_end count=2 wall_ms=4 work_ms=4 online_at_creation=0\n[regular] all_online count=2 after_create_ms=30\n'
            path=app/'logs/test.log'; path.write_text(log)
            result=regular.summarize(root)
            self.assertEqual(result['retainedOnlineClient'],2)
            self.assertEqual(result['frameMs']['mean'],1000)
            self.assertEqual(result['creationWarmupMaxFrameMs'],200)
            self.assertEqual(result['postCreationMaxFrameMs'],10)
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
            frame_rows[3]=(9,3000,4,1000,1)
            write(app/'regular-frames.csv','frame,game_ms,stage,frame_ms,frame_gap',frame_rows)
            with self.assertRaisesRegex(ValueError,'Missing frames'): regular.summarize(root)


if __name__=='__main__': unittest.main()
