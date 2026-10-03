"""Test the production implementation, without duplicating it."""
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text(encoding='utf-8')
start = source.rfind('\n', 0, source.index('xrDebug::DXerror2string(')) + 1
opening = source.index('{', start)
depth, end = 1, opening + 1
while depth:
    depth += (source[end] == '{') - (source[end] == '}')
    end += 1
Path(sys.argv[2]).write_text(source[start:end], encoding='utf-8')
