from pathlib import Path
import sys
here = Path(__file__).resolve().parent
root = here.parents[2]
def region(path, start, end):
    source = (root/path).read_text(encoding='utf-8')
    if source.count(start) != 1 or source.count(end) != 1: raise ValueError('Production boundaries changed')
    return start + source.split(start, 1)[1].split(end, 1)[0]
a = region('ogsr_engine/xrGame/alife_dynamic_object.cpp', '\nvoid CSE_ALifeDynamicObject::try_switch_online()', '\nbool CSE_ALifeDynamicObject::redundant()')
Path(sys.argv[1]).write_text(a.replace('CSE_ALifeDynamicObject::','Candidate::'), encoding='utf-8')
b = region('ogsr_engine/xrGame/alife_group_abstract.cpp', '\nvoid CSE_ALifeGroupAbstract::try_switch_offline()', '\nbool CSE_ALifeGroupAbstract::redundant()')
Path(sys.argv[2]).write_text(b.replace('CSE_ALifeGroupAbstract::','Candidate::'), encoding='utf-8')
c = region('ogsr_engine/xrGame/alife_switch_manager.cpp', '\nvoid CALifeSwitchManager::try_switch_online(', '\nvoid CALifeSwitchManager::try_switch_offline(')
Path(sys.argv[3]).write_text(c.replace('CALifeSwitchManager::','Manager::'), encoding='utf-8')

d = region('ogsr_engine/xrGame/alife_online_offline_group.cpp', '\nvoid CSE_ALifeOnlineOfflineGroup::try_switch_online()', '\nvoid CSE_ALifeOnlineOfflineGroup::switch_online()')
Path(sys.argv[4]).write_text(d.replace('CSE_ALifeOnlineOfflineGroup::','Candidate::'), encoding='utf-8')
