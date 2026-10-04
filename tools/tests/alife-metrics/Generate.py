from pathlib import Path
import re
import sys
root = Path(__file__).resolve().parents[3]
def method(source, name):
    matches = list(re.finditer(r"\n(?:bool|void) " + re.escape(name) + r"\(", source))
    if len(matches) != 1:
        raise ValueError(f"Expected one production method: {name}")
    start = matches[0].start() + 1
    end = source.find("\n}", start)
    if end < 0:
        raise ValueError(f"Missing method boundary: {name}")
    return source[start:end + 2] + "\n"
source = (root/'ogsr_engine/xrGame/alife_switch_manager.cpp').read_text(encoding='utf-8')
body = '\n'.join(method(source, 'CALifeSwitchManager::' + name) for name in
    ['maintain_before_switch', 'evaluate_switch', 'maintain_after_switch', 'switch_object'])
Path(sys.argv[1]).write_text(body.replace('CALifeSwitchManager::', 'Candidate::'), encoding='utf-8')
source = (root/'ogsr_engine/xrGame/alife_update_manager.cpp').read_text(encoding='utf-8')
Path(sys.argv[2]).write_text(method(source, 'CALifeUpdateManager::update'), encoding='utf-8')
