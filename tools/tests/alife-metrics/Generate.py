from pathlib import Path
import sys
root = Path(__file__).resolve().parents[3]
def region(source, start, end):
    if source.count(start) != 1 or source.count(end) != 1:
        raise ValueError('Production boundaries changed; inspect fixture')
    return start + source.split(start, 1)[1].split(end, 1)[0]
import re
source = (root/'ogsr_engine/xrGame/alife_switch_manager.cpp').read_text(encoding='utf-8')
body = region(source, '\nbool CALifeSwitchManager::maintain_before_switch(', '\nvoid CALifeSwitchManager::begin_reconciliation(')
body = re.sub(r'^(bool|void) CALifeSwitchManager::', r'\1 Candidate::', body, flags=re.MULTILINE)
Path(sys.argv[1]).write_text(body, encoding='utf-8')
source = (root/'ogsr_engine/xrGame/alife_update_manager.cpp').read_text(encoding='utf-8')
Path(sys.argv[2]).write_text(region(source, '\nvoid CALifeUpdateManager::update()', '\nvoid CALifeUpdateManager::report_metrics()'), encoding='utf-8')
