"""Synthetic scheduler evidence; never opens game saves or a live session."""
import csv
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('cadence', Path(__file__).with_name('Summarize-Cadence.py'))
cadence = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cadence)


def write_csv(path, fields, values):
    with path.open('w', newline='', encoding='utf-8') as stream:
        writer = csv.writer(stream)
        writer.writerow(fields.split(','))
        writer.writerows(values)


class EvidenceTests(unittest.TestCase):
    def test_zero_update_npc_is_not_dropped_and_death_is_not_starvation(self):
        with tempfile.TemporaryDirectory(prefix='ogsr-cadence-fixture-') as directory:
            root = Path(directory)
            (root/'appdata/logs').mkdir(parents=True)
            (root/'session.json').write_text(json.dumps(dict(status='stress-completed', cadenceRequested=True,
                session='synthetic', scenario='dispersed', requestedExtraStalkers=3)))
            (root/'appdata/logs/test.log').write_text('[stress spawn] id=1\n[stress spawn] id=2\n[stress spawn] id=3\n')
            times = range(1000, 27000, 1000)
            write_csv(root/'appdata/cadence-cohort.csv', 'game_ms,stage,id,alive,health,x,y,z,enemy',
                      [(time,3,npc,int(npc!=3 or time<13000),1,0,0,0,65535) for time in times for npc in (1,2,3)])
            fields = 'game_ms,dispatch_ms,id,alive,enemy,firing,engine_interval_ms,requested_ms,late_ms,next_ms,realtime,context_valid'
            updates = [(time,time+5,1,1,65535,0,1000,1000,5,1000,0,1) for time in times]
            write_csv(root/'appdata/cadence-updates.csv', fields, updates)
            write_csv(root/'appdata/cadence-scheduler.csv', 'game_ms,budget_stopped,pending,overdue,max_late_ms,budget_ms',
                      [(time,0,3,0,0,3) for time in times])
            result = cadence.summarize(root)
            self.assertEqual(result['persistentLivingNpcs'], 2)
            self.assertEqual(result['zeroUpdateIds'], [2])
            self.assertEqual(result['actualIntervalMs']['median'], 1000)
            self.assertEqual(result['lateMs']['max'], 5)
            self.assertEqual(result['npcMaxSilentGapMs']['max'], 25000)
            write_csv(root/'appdata/cadence-updates.csv', fields, [updates[0][:-1]+(0,)])
            with self.assertRaisesRegex(ValueError, 'matching scheduler context'):
                cadence.summarize(root)


if __name__ == '__main__':
    unittest.main()
