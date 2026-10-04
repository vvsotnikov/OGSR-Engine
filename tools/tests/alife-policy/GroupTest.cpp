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
struct Candidate : CSE_ALifeGroupAbstract { void try_switch_offline(); };
#include "group-methods.inc"
int main()
{
    for (bool distanceMode : {false, true})
        for (bool groupAllowed : {false, true})
            for (bool near : {false, true})
                for (bool deadFirst : {false, true})
                {
                    World state;
                    Candidate group;
                    state.current = &group; state.distance = distanceMode;
                    state.group.offlinePermission = true;
                    state.group.onlinePermission = groupAllowed;
                    group.m_wCount = 2;
                    group.m_tpMembers = deadFirst ? std::vector<int>{1, 0} : std::vector<int>{0, 1};
                    auto& living = state.members[0];
                    living.CSE_ALifeDynamicObject::id = living.CSE_ALifeInventoryItem::id = 0;
                    living.monster = true; living.alive = true;
                    living.onlinePermission = living.offlinePermission = true;
                    living.o_Position.value = near ? 149.f : 151.f;
                    auto& dead = state.members[1];
                    dead.CSE_ALifeDynamicObject::id = dead.CSE_ALifeInventoryItem::id = 1;
                    dead.monster = true; dead.alive = false; dead.inventory = false;
                    world = &state;
                    group.try_switch_offline();
                    const bool blocks = !distanceMode || near;
                    // A blocking member stops later corpse cleanup; a corpse before
                    // it is detached. Group permission can still force the final switch.
                    check(group.m_wCount == (deadFirst || !blocks ? 1u : 2u));
                    check(state.group.m_bOnline == !(groupAllowed || !blocks));
                }
    std::cout << "Legacy group policy and corpse-order cases passed\n";
}
