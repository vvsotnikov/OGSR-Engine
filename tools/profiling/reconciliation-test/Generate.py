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

# Slice complete, explicitly delimited source regions; fail if their boundaries
# move rather than trying to parse C++ braces, comments or string literals.
path = 'ogsr_engine/xrGame/alife_group_abstract.cpp'
old = subprocess.check_output(['git', '-C', str(root), 'show', 'b6e73fac6:' + path], text=True)
new = (root / path).read_text(encoding='utf-8')
def region(source, start, end):
    if source.count(start) != 1 or source.count(end) != 1:
        raise ValueError('Group fixture source boundaries changed; inspect extraction')
    return source.split(start, 1)[1].split(end, 1)[0]

signature = 'void CSE_ALifeGroupAbstract::try_switch_offline()'
end = '\nbool CSE_ALifeGroupAbstract::redundant()'
baseline = signature + region(old, signature, end)
candidate = 'namespace\n{' + region(new, '\nnamespace\n{', end)
Path(sys.argv[2]).write_text(
    baseline.replace(signature, 'void Baseline::try_switch_offline()') + '\n' +
    candidate.replace(signature, 'void Candidate::try_switch_offline()'), encoding='utf-8')
