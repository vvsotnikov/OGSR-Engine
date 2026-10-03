#include <array>
#include <iostream>
#include <limits>
#include <stdexcept>
#include <string>
#include <type_traits>
#include <vector>
using u32 = unsigned;
void check(bool ok) { if (!ok) throw std::runtime_error("legacy group behavior mismatch"); }
#define VERIFY(x) check(bool(x))
struct World;
World* world;
void log(const std::string& text);
struct Position { float value = 0; float distance_to(const Position& other) const { log("distance"); return other.value; } };
struct Simulator;
struct CSE_ALifeInventoryItem
{
    int id = 0;
    bool isAttached = false;
    bool attached() { log("attached:" + std::to_string(id)); return isAttached; }
};
struct CSE_ALifeDynamicObject
{
    int id = 0, ID_Parent = -1, m_tGraphID = 17;
    bool onlinePermission = true, offlinePermission = true, m_bOnline = true, m_bDirectControl = false;
    Position o_Position;
    virtual ~CSE_ALifeDynamicObject() = default;
    bool can_switch_online() { log("can_online:" + std::to_string(id)); return onlinePermission; }
    bool can_switch_offline() { log("can_offline:" + std::to_string(id)); return offlinePermission; }
    Simulator& alife();
    void detach(CSE_ALifeInventoryItem*);
};
struct CSE_ALifeMonsterAbstract : CSE_ALifeDynamicObject, CSE_ALifeInventoryItem
{
    bool monster = true, inventory = false, alive = true;
    float fHealth = 1;
    bool g_Alive() { log("alive:" + std::to_string(CSE_ALifeDynamicObject::id)); return alive; }
};
struct CSE_ALifeGroupAbstract
{
    std::vector<int> m_tpMembers;
    unsigned m_wCount = 0;
    CSE_ALifeDynamicObject* base();
};
struct Registry { CSE_ALifeDynamicObject* object(int id, bool optional = false); };
struct Graph
{
    CSE_ALifeDynamicObject* actor();
    void remove(CSE_ALifeMonsterAbstract*, int, bool);
};
struct Simulator
{
    Registry registry; Graph graphValue;
    Registry& objects() { return registry; }
    Graph& graph() { return graphValue; }
    bool uses_distance_switching();
    float offline_distance() { log("threshold"); return 150; }
    void register_object(CSE_ALifeMonsterAbstract*);
    void switch_offline(CSE_ALifeDynamicObject*);
};
struct AI { Simulator& alife(); };
AI& ai() { static AI instance; return instance; }
struct World
{
    Simulator simulator;
    CSE_ALifeDynamicObject group, parent, actor;
    std::array<CSE_ALifeMonsterAbstract, 3> members;
    CSE_ALifeGroupAbstract* current = nullptr;
    bool distance = true, parentExists = true;
    int registrationAttachment = 0;
    std::vector<std::string> events;
};
void log(const std::string& text) { world->events.push_back(text); }
Simulator& CSE_ALifeDynamicObject::alife() { return world->simulator; }
Simulator& AI::alife() { return world->simulator; }
CSE_ALifeDynamicObject* CSE_ALifeGroupAbstract::base() { return &world->group; }
CSE_ALifeDynamicObject* Registry::object(int id, bool optional)
{
    log("lookup:" + std::to_string(id) + ":" + std::to_string(optional));
    if (id == 99) return world->parentExists ? &world->parent : nullptr;
    return &world->members.at(id);
}
CSE_ALifeDynamicObject* Graph::actor() { return &world->actor; }
bool Simulator::uses_distance_switching() { log("distance_mode"); return world->distance; }
std::string state(const CSE_ALifeMonsterAbstract& member)
{
    std::string result = std::to_string(member.CSE_ALifeDynamicObject::id) + ":" +
        std::to_string(member.fHealth) + ":" + std::to_string(member.m_bOnline) + ":" +
        std::to_string(member.m_bDirectControl) + ":" + std::to_string(member.isAttached) + ":" +
        std::to_string(world->current->m_wCount);
    for (int id : world->current->m_tpMembers) result += ":member" + std::to_string(id);
    return result;
}
void CSE_ALifeDynamicObject::detach(CSE_ALifeInventoryItem* item)
{
    log("detach:" + state(world->members.at(item->id)));
    item->isAttached = false;
}
void Simulator::register_object(CSE_ALifeMonsterAbstract* member)
{
    log("register:" + state(*member));
    if (world->registrationAttachment == 1) member->isAttached = false;
    if (world->registrationAttachment == 2) member->isAttached = true;
}
void Graph::remove(CSE_ALifeMonsterAbstract* member, int graph, bool update)
{
    log("graph_remove:" + state(*member) + ":" + std::to_string(graph) + ":" + std::to_string(update));
}
void Simulator::switch_offline(CSE_ALifeDynamicObject* object) { log("switch_offline"); object->m_bOnline = false; }
template<class T, class U> T smart_cast(U* object)
{
    if constexpr (std::is_same_v<T, CSE_ALifeDynamicObject*>) return object;
    else
    {
        auto member = dynamic_cast<CSE_ALifeMonsterAbstract*>(object);
        if constexpr (std::is_same_v<T, CSE_ALifeMonsterAbstract*>) return member && member->monster ? member : nullptr;
        else return member && member->inventory ? static_cast<CSE_ALifeInventoryItem*>(member) : nullptr;
    }
}
struct Baseline : CSE_ALifeGroupAbstract { void try_switch_offline(); };
struct Candidate : CSE_ALifeGroupAbstract { void try_switch_offline(); };
#include "group-methods.inc"
int main()
{
    unsigned cases = 0;
    // All ordered triples of eleven member states, plus all shorter prefixes.
    for (unsigned length = 0; length <= 3; ++length)
    {
        unsigned combinations = 1;
        for (unsigned i = 0; i < length; ++i) combinations *= 11;
        for (unsigned code = 0; code < combinations; ++code)
            for (unsigned flags = 0; flags < 16; ++flags)
                for (int attachment = 0; attachment < 3; ++attachment)
                {
                    World original;
                    original.group.id = 98;
                    original.group.onlinePermission = flags & 1;
                    original.group.offlinePermission = flags & 2;
                    original.distance = flags & 4;
                    original.parentExists = flags & 8;
                    original.registrationAttachment = attachment;
                    Baseline a; Candidate b;
                    a.m_wCount = b.m_wCount = length;
                    unsigned value = code;
                    for (unsigned i = 0; i < length; ++i)
                    {
                        unsigned kind = value % 11; value /= 11;
                        auto& m = original.members[i];
                        m.CSE_ALifeDynamicObject::id = m.CSE_ALifeInventoryItem::id = i;
                        m.ID_Parent = 99;
                        m.monster = kind != 0;
                        m.alive = kind < 7;
                        m.offlinePermission = kind != 1;
                        m.onlinePermission = kind != 2;
                        m.o_Position.value = kind == 4 ? 151.f : kind == 5 ? 150.f : kind == 6 ? std::numeric_limits<float>::quiet_NaN() : 149.f;
                        m.inventory = kind >= 8;
                        m.isAttached = kind >= 9;
                        m.fHealth = m.alive ? 1.f : kind == 10 ? 0.f : -1.f;
                        a.m_tpMembers.push_back(i); b.m_tpMembers.push_back(i);
                    }
                    World candidate = original;
                    original.current = &a; candidate.current = &b;
                    world = &original; a.try_switch_offline();
                    world = &candidate; b.try_switch_offline();
                    check(original.events == candidate.events);
                    check(a.m_tpMembers == b.m_tpMembers && a.m_wCount == b.m_wCount);
                    check(original.group.m_bOnline == candidate.group.m_bOnline);
                    // Independent characterization of the surprising legacy rule:
                    // a blocking live member leaves later corpses untouched, yet
                    // the group's own online permission still permits switching.
                    if (length == 2 && flags == 3 && attachment == 0 && code == 3 + 7 * 11)
                        check(b.m_wCount == 2 && b.m_tpMembers == std::vector<int>({0, 1}) && !candidate.group.m_bOnline);
                    if (length == 2 && flags == 3 && attachment == 0 && code == 7 + 3 * 11)
                        check(b.m_wCount == 1 && b.m_tpMembers == std::vector<int>({1}) && !candidate.group.m_bOnline);
                    for (unsigned i = 0; i < length; ++i)
                    {
                        world = &original; auto before = state(original.members[i]);
                        world = &candidate; check(before == state(candidate.members[i]));
                    }
                    ++cases;
                }
    }
    std::cout << cases << " legacy group comparisons passed\n";
}
