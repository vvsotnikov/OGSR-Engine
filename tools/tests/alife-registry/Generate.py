from pathlib import Path
import sys
root = Path(__file__).resolve().parents[3]
def region(source, start, end):
    if source.count(start) != 1 or source.count(end) != 1:
        raise ValueError('Production boundaries changed; inspect fixture')
    return start + source.split(start, 1)[1].split(end, 1)[0]
source = (root/'ogsr_engine/xrGame/alife_object_registry.cpp').read_text(encoding='utf-8')
Path(sys.argv[1]).write_text(region(source, '\nCALifeObjectRegistry::~CALifeObjectRegistry()', '\nvoid CALifeObjectRegistry::save(IWriter& memory_stream,'), encoding='utf-8')
