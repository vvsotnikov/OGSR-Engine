"""Compile production method bodies against deterministic lifecycle operations."""
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parents[3]
path = 'ogsr_engine/xrGame/alife_dynamic_object.cpp'
old = subprocess.check_output(['git', '-C', str(root), 'show', '0924e934b:' + path], text=True)
new = (root / path).read_text()

def extract(source, name, replacement):
    signature = 'CSE_ALifeDynamicObject::' + name + '('
    start = source.rfind('\n', 0, source.index(signature)) + 1
    opening = source.index('{', start)
    depth, end = 1, opening + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    signature_line, body = source[start:end].split('\n', 1)
    return signature_line.replace('CSE_ALifeDynamicObject::', replacement + '::') + '\n' + body

result = '\n'.join(extract(old, n, 'Baseline') for n in ['try_switch_online', 'try_switch_offline'])
result += '\n' + '\n'.join(extract(new, n, 'Candidate') for n in [
    'maintain_offline_schedule', 'evaluate_online_switch', 'try_switch_online',
    'evaluate_offline_switch', 'try_switch_offline'])
Path(sys.argv[1]).write_text(result)
