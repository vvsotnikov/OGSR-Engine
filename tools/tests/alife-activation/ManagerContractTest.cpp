#include "../../../ogsr_engine/xrGame/alife_activation_queue.h"
#include <map>
#include <stdexcept>
#include <vector>
#include <iostream>
#define START_PROFILE(...)
#define STOP_PROFILE
#define VERIFY2(...)
#define ZoneScopedN(...)
#define TracyPlot(...)
constexpr unsigned INVALID_STORY_ID = ~0u;
struct { unsigned dwPrecacheFrame = 0; } Device;
struct Manager;
struct CSE_ALifeDynamicObject
{
    unsigned ID = 7, ID_Parent = 0xffff, m_story_id = INVALID_STORY_ID;
    bool m_bOnline = false, allowed = true, keep = false, requests = true;
    bool invalid_location = false, obsolete = false, released = false;
    unsigned attempts = 0;
    Manager* manager = nullptr;
    std::vector<unsigned char> client_data{1, 2, 3};
    bool can_switch_online() const { return allowed; }
    bool keep_saved_data_anyway() const { return keep; }
    bool redundant() const { return obsolete; }
    void try_switch_online();
};
struct Registry
{
    std::map<unsigned, CSE_ALifeDynamicObject*> values;
    bool first = false, expired = false;
    bool first_update() const { return first; }
    bool time_over() const { return expired; }
    CSE_ALifeDynamicObject* object(unsigned id, bool) {
        auto entry = values.find(id);
        return entry == values.end() ? nullptr : entry->second;
    }
};
struct Graph
{
    Registry registry;
    CSE_ALifeDynamicObject actor_object;
    Graph() { actor_object.ID = 0; actor_object.m_bOnline = true; }
    Registry& level() { return registry; }
    CSE_ALifeDynamicObject* actor() { return &actor_object; }
};
struct Manager
{
#include "limit.inc"
    ALifeActivationQueue m_activation_queue;
    bool m_activation_queue_enabled = false, m_collect_activations = false;
    Registry global;
    Graph world;
    unsigned activated = 0, checked = 0;
    Registry& objects() { return global; }
    Graph& graph() { return world; }
    bool synchronize_location(CSE_ALifeDynamicObject* object) { ++checked; return !object->invalid_location; }
    void release(CSE_ALifeDynamicObject* object) { object->released = true; global.values.erase(object->ID); world.registry.values.erase(object->ID); }
    void switch_online(CSE_ALifeDynamicObject* object) { ++activated; object->m_bOnline = true; }
    void try_switch_offline(CSE_ALifeDynamicObject*) {}
    void try_switch_online(CSE_ALifeDynamicObject*);
    void request_switch_online(CSE_ALifeDynamicObject*);
    void begin_activation_collection();
    void finish_activation_collection();
    void switch_object(CSE_ALifeDynamicObject*);
    void add(CSE_ALifeDynamicObject& object) {
        object.manager = this;
        global.values[object.ID] = &object;
        world.registry.values[object.ID] = &object;
    }
};
// Virtual eligibility is supplied by the object; manager request/consume paths below are production code.
void CSE_ALifeDynamicObject::try_switch_online() {
    ++attempts;
    if (allowed && requests) manager->request_switch_online(this);
}
#include "online-method.inc"
void check(bool condition) { if (!condition) throw std::runtime_error("activation manager contract"); }
int main()
{
    for (bool deferred : {false, true})
    for (bool attached : {false, true})
    for (bool allowed : {false, true})
    for (bool keep : {false, true})
    for (bool requests : {false, true})
    {
        Manager manager;
        CSE_ALifeDynamicObject object;
        manager.add(object);
        manager.m_collect_activations = deferred;
        object.ID_Parent = attached ? 1 : 0xffff;
        object.allowed = allowed; object.keep = keep; object.requests = requests;
        manager.m_activation_queue.enqueue(object.ID);
        manager.try_switch_online(&object);
        const bool queued = !attached && deferred && allowed && requests;
        const bool online = !attached && !deferred && allowed && requests;
        check(manager.m_activation_queue.contains(object.ID) == queued);
        check(object.m_bOnline == online);
        check(object.client_data.empty() == (!attached && !queued && !online && !keep));
        check(object.attempts == (attached ? 0u : 1u));
    }
    for (unsigned bypass = 0; bypass < 2; ++bypass)
    {
        Manager manager;
        CSE_ALifeDynamicObject object;
        auto* target = bypass == 0 ? manager.graph().actor() : &object;
        manager.add(*target); target->m_bOnline = false;
        if (bypass == 1) target->m_story_id = 1;
        manager.m_collect_activations = true;
        manager.request_switch_online(target);
        check(target->m_bOnline && manager.m_activation_queue.size() == 0);
    }
    for (unsigned loading = 0; loading < 3; ++loading)
    {
        Manager manager;
        manager.m_activation_queue_enabled = true;
        manager.m_activation_queue.enqueue(7);
        manager.world.registry.first = loading == 0;
        Device.dwPrecacheFrame = loading == 1 ? 1 : 0;
        manager.world.actor_object.m_bOnline = loading != 2;
        manager.begin_activation_collection();
        check(!manager.m_collect_activations && manager.m_activation_queue.slots() == 0);
        Device.dwPrecacheFrame = 0;
    }
    for (unsigned state = 0; state < 7; ++state)
    {
        Manager manager;
        CSE_ALifeDynamicObject original, replacement;
        manager.add(original);
        manager.m_activation_queue_enabled = true;
        manager.begin_activation_collection();
        manager.request_switch_online(&original);
        check(!original.m_bOnline && manager.m_activation_queue.contains(7));
        if (state == 0) manager.global.values.clear(); // released ID
        if (state == 1) original.m_bOnline = true;
        if (state == 2) manager.world.registry.values.clear(); // moved to another level
        if (state == 3) original.ID_Parent = 1;
        if (state == 4) original.allowed = false;
        if (state == 5) original.invalid_location = true;
        if (state == 6) manager.add(replacement); // reused ID resolves current object
        manager.world.registry.expired = true;
        manager.finish_activation_collection();
        check(!manager.m_collect_activations && manager.m_activation_queue.size() == 0);
        check(manager.activated == (state == 6 ? 1u : 0u));
        check(manager.checked == (state >= 3 ? 1u : 0u));
        if (state == 2 || state == 3) check(!original.client_data.empty());
        if (state == 6) check(replacement.m_bOnline && !original.m_bOnline);
    }
    Manager manager;
    CSE_ALifeDynamicObject first, second;
    second.ID = 8;
    manager.add(first); manager.add(second);
    manager.m_activation_queue_enabled = true;
    manager.begin_activation_collection();
    manager.request_switch_online(&first); manager.request_switch_online(&second);
    manager.world.registry.expired = true;
    manager.finish_activation_collection();
    check(first.m_bOnline && !second.m_bOnline && manager.m_activation_queue.size() == 1);
    manager.begin_activation_collection(); manager.finish_activation_collection();
    check(second.m_bOnline && manager.m_activation_queue.size() == 0);
    std::cout << "manager eligibility, lifecycle, saved state and expiry checks passed\n";
}
