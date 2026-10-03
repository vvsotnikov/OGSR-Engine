"""Compile production regions against frozen references, without Git history."""
from pathlib import Path
import re
import sys
here = Path(__file__).resolve().parent
root = here.parents[2]
def region(source, start, end):
    if source.count(start) != 1 or source.count(end) != 1:
        raise ValueError('Production region boundaries changed; inspect fixture')
    return start + source.split(start, 1)[1].split(end, 1)[0]
source = (root / 'ogsr_engine/xrGame/alife_switch_manager.cpp').read_text(encoding='utf-8')
candidate = region(source, '\nbool CALifeSwitchManager::maintain_before_switch(', '\nvoid CALifeSwitchManager::begin_reconciliation(')
candidate = re.sub(r'^(bool|void) CALifeSwitchManager::', r'\1 Candidate::', candidate, flags=re.MULTILINE)
Path(sys.argv[1]).write_text((here / 'Baseline.inc').read_text(encoding='utf-8') + candidate, encoding='utf-8')
source = (root / 'ogsr_engine/xrGame/alife_group_abstract.cpp').read_text(encoding='utf-8')
candidate = region(source, '\nnamespace\n{', '\nbool CSE_ALifeGroupAbstract::redundant()')
candidate = candidate.replace('void CSE_ALifeGroupAbstract::try_switch_offline()', 'void Candidate::try_switch_offline()')
Path(sys.argv[2]).write_text((here / 'GroupBaseline.inc').read_text(encoding='utf-8') + candidate, encoding='utf-8')
