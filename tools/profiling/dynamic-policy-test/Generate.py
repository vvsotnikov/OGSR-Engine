"""Compile current policy against a checked-in pre-refactor reference."""
from pathlib import Path
import re
import sys
here = Path(__file__).resolve().parent
root = here.parents[2]
source = (root / 'ogsr_engine/xrGame/alife_dynamic_object.cpp').read_text(encoding='utf-8')
start = '\nvoid CSE_ALifeDynamicObject::maintain_offline_schedule()'
end = '\nbool CSE_ALifeDynamicObject::redundant()'
if source.count(start) != 1 or source.count(end) != 1:
    raise ValueError('Production region boundaries changed; inspect fixture')
candidate = start + source.split(start, 1)[1].split(end, 1)[0]
candidate = re.sub(r'^(?:void|bool|CSE_ALifeDynamicObject::OnlineSwitchDecision) CSE_ALifeDynamicObject::.*$',
    lambda m: m[0].replace('CSE_ALifeDynamicObject::', 'Candidate::'), candidate, flags=re.MULTILINE)
Path(sys.argv[1]).write_text((here / 'Baseline.inc').read_text(encoding='utf-8') + candidate, encoding='utf-8')
