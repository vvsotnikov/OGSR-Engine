"""Extract real old/new manager methods; do not duplicate their control flow."""
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parents[3]
path = 'ogsr_engine/xrGame/alife_switch_manager.cpp'
old = subprocess.check_output(['git', '-C', str(root), 'show', 'd89893ca1:' + path], text=True)
new = (root / path).read_text()

def extract(source, name, replacement):
    signature = 'CALifeSwitchManager::' + name + '('
    start = source.rfind('\n', 0, source.index(signature)) + 1
    opening = source.index('{', start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end].replace('CALifeSwitchManager::', replacement + '::')

result = extract(old, 'switch_object', 'Baseline') + '\n'
for name in ['maintain_before_switch', 'evaluate_switch', 'maintain_after_switch', 'switch_object']:
    result += extract(new, name, 'Candidate') + '\n'
Path(sys.argv[1]).write_text(result)
