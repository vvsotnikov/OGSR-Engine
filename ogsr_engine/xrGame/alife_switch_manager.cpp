////////////////////////////////////////////////////////////////////////////
//	Module 		: alife_switch_manager.cpp
//	Created 	: 25.12.2002
//  Modified 	: 12.05.2004
//	Author		: Dmitriy Iassenev
//	Description : ALife Simulator switch manager
////////////////////////////////////////////////////////////////////////////

#include "stdafx.h"
#include "alife_service_trace.h"
#include "alife_switch_lifecycle.h"
#include "alife_switch_manager.h"
#include "xrServer_Objects_ALife.h"
#include "alife_graph_registry.h"
#include "alife_object_registry.h"
#include "alife_schedule_registry.h"
#include "game_level_cross_table.h"
#include "xrserver.h"
#include "ai_space.h"
#include "level_graph.h"

#ifdef DEBUG
#include "level.h"
#endif // DEBUG

using namespace ALife;

struct remove_non_savable_predicate
{
    xrServer* m_server;

    IC remove_non_savable_predicate(xrServer* server)
    {
        VERIFY(server);
        m_server = server;
    }

    IC bool operator()(const ALife::_OBJECT_ID& id) const
    {
        CSE_Abstract* object = m_server->game->get_entity_from_eid(id);
        VERIFY(object);
        CSE_ALifeObject* alife_object = smart_cast<CSE_ALifeObject*>(object);
        VERIFY(alife_object);
        return (!alife_object->can_save());
    }
};

CALifeSwitchManager::~CALifeSwitchManager() {}

void CALifeSwitchManager::add_online(CSE_ALifeDynamicObject* object, bool update_registries)
{
    START_PROFILE("ALife/switch/add_online")
    VERIFY((ai().game_graph().vertex(object->m_tGraphID)->level_id() == graph().level().level_id()));

    object->m_bOnline = true;
    alife_service_trace::event("online", object->ID);

    NET_Packet tNetPacket;
    CSE_Abstract* l_tpAbstract = smart_cast<CSE_Abstract*>(object);
    server().entity_Destroy(l_tpAbstract);
    object->s_flags.Or(M_SPAWN_UPDATE);
    ClientID clientID;
    clientID.set(server().GetServerClient() ? server().GetServerClient()->ID.value() : 0);
    server().Process_spawn(tNetPacket, clientID, FALSE, l_tpAbstract);
    object->s_flags.And(u16(-1) ^ M_SPAWN_UPDATE);

    if (object->used_ai_locations() && !ai().level_graph().valid_vertex_id(object->m_tNodeID))
    {
        Msg("Trying to correct invalid vertex %u for object %s", object->m_tNodeID, object->name_replace());
        object->m_tNodeID = ai().level_graph().vertex_id(object->m_tNodeID, object->o_Position);
        Msg("  new vertex: %u", object->m_tNodeID);
    }
    ASSERT_FMT(!object->used_ai_locations() || ai().level_graph().valid_vertex_id(object->m_tNodeID), "Invalid vertex %u for object %s", object->m_tNodeID, object->name_replace());

#ifdef DEBUG
    if (psAI_Flags.test(aiALife))
        Msg("[LSS] Spawning object [%s][%s][%d]", object->name_replace(), *object->s_name, object->ID);
#endif

    object->add_online(update_registries);
    if (m_alife_metrics) ++m_online_switches;
    STOP_PROFILE
}

void CALifeSwitchManager::remove_online(CSE_ALifeDynamicObject* object, bool update_registries)
{
    START_PROFILE("ALife/switch/remove_online")
    object->m_bOnline = false;
    alife_service_trace::event("offline", object->ID);

    m_saved_chidren = object->children;
    CSE_ALifeTraderAbstract* inventory_owner = smart_cast<CSE_ALifeTraderAbstract*>(object);
    CSE_InventoryBox* inventory_box = smart_cast<CSE_InventoryBox*>(object);
    CSE_InventoryContainer* inventory_cont = smart_cast<CSE_InventoryContainer*>(object);

    if (inventory_owner || inventory_box || inventory_cont)
    {
        m_saved_chidren.erase(std::remove_if(m_saved_chidren.begin(), m_saved_chidren.end(), remove_non_savable_predicate(&server())), m_saved_chidren.end());
    }

    server().Perform_destroy(object, net_flags(TRUE, TRUE));
    VERIFY(object->children.empty());

    _OBJECT_ID object_id = object->ID;
    object->ID = server().PerformIDgen(object_id);

#ifdef DEBUG
    if (psAI_Flags.test(aiALife))
        Msg("[LSS] Destroying object [%s][%s][%d]", object->name_replace(), *object->s_name, object->ID);
#endif

    object->add_offline(m_saved_chidren, update_registries);
    if (m_alife_metrics) ++m_offline_switches;
    STOP_PROFILE
}

void CALifeSwitchManager::switch_online(CSE_ALifeDynamicObject* object)
{
    START_PROFILE("ALife/switch/switch_online")
#ifdef DEBUG
    //	if (psAI_Flags.test(aiALife))
    Msg("[LSS][%d] Going online [%d][%s][%d] ([%f][%f][%f] : [%f][%f][%f]), on '%s'", Device.dwFrame, Device.dwTimeGlobal, object->name_replace(), object->ID,
        VPUSH(graph().actor()->o_Position), VPUSH(object->o_Position), "*SERVER*");
#endif
    object->switch_online();
    STOP_PROFILE
}

void CALifeSwitchManager::switch_offline(CSE_ALifeDynamicObject* object)
{
    START_PROFILE("ALife/switch/switch_offline")
#ifdef DEBUG
    //	if (psAI_Flags.test(aiALife))
    Msg("[LSS][%d] Going offline [%d][%s][%d] ([%f][%f][%f] : [%f][%f][%f]), on '%s'", Device.dwFrame, Device.dwTimeGlobal, object->name_replace(), object->ID,
        VPUSH(graph().actor()->o_Position), VPUSH(object->o_Position), "*SERVER*");
#endif
    object->switch_offline();
    STOP_PROFILE
}

bool CALifeSwitchManager::synchronize_location(CSE_ALifeDynamicObject* I)
{
    START_PROFILE("ALife/switch/synchronize_location")
#ifdef DEBUG
    VERIFY3(ai().level_graph().level_id() == ai().game_graph().vertex(I->m_tGraphID)->level_id(), *I->s_name, I->name_replace());
    if (!I->children.empty())
    {
        u32 size = I->children.size();
        ALife::_OBJECT_ID* test = (ALife::_OBJECT_ID*)_alloca(size * sizeof(ALife::_OBJECT_ID));
        Memory.mem_copy(test, &*I->children.begin(), size * sizeof(ALife::_OBJECT_ID));
        std::sort(test, test + size);
        for (u32 i = 1; i < size; ++i)
        {
            VERIFY3(test[i - 1] != test[i], "Child is registered twice in the child list", (*I).name_replace());
        }
    }
#endif // DEBUG

    // check if we do not use ai locations
    if (!I->used_ai_locations())
        return (true);

    // check if we are not attached
    if (0xffff != I->ID_Parent)
        return (true);

    // check if we are not online and have an invalid level vertex id
    if (!I->m_bOnline && !ai().level_graph().valid_vertex_id(I->m_tNodeID))
        return (true);

    return ((*I).synchronize_location());
    STOP_PROFILE
}

void CALifeSwitchManager::try_switch_online(CSE_ALifeDynamicObject* I)
{
    START_PROFILE("ALife/switch/try_switch_online")
    struct Operations
    {
        CALifeSwitchManager& manager;
        CSE_ALifeDynamicObject* I;
        bool attached() const { return I->ID_Parent != 0xffff; }
        void verify_parent() const
        {
#ifdef DEBUG
            if (psAI_Flags.test(aiALife))
            {
                CSE_ALifeCreatureAbstract* l_tpALifeCreatureAbstract = smart_cast<CSE_ALifeCreatureAbstract*>(manager.objects().object(I->ID_Parent));
                if (l_tpALifeCreatureAbstract && (l_tpALifeCreatureAbstract->fHealth < EPS_L))
                    Msg("! uncontrolled situation [%d][%d][%s][%f]", I->ID, I->ID_Parent, l_tpALifeCreatureAbstract->name_replace(), l_tpALifeCreatureAbstract->fHealth);
                VERIFY2(!l_tpALifeCreatureAbstract || (l_tpALifeCreatureAbstract->fHealth >= EPS_L), "Parent online, item offline...");
                if (manager.objects().object(I->ID_Parent)->m_bOnline)
                    Msg("! uncontrolled situation [%d][%d][%s][%f]", I->ID, I->ID_Parent, l_tpALifeCreatureAbstract->name_replace(), l_tpALifeCreatureAbstract->fHealth);
            }
            VERIFY2(!manager.objects().object(I->ID_Parent)->m_bOnline, "Parent online, item offline...");
#endif
        }
        void verify_offline() const
        {
            VERIFY2((ai().game_graph().vertex(I->m_tGraphID)->level_id() != ai().level_graph().level_id()) || !Level().Objects.net_Find(I->ID) || Level().Objects.dump_all_objects(),
                    make_string("frame [%d] time [%d] object [%s] with id [%d] is offline, but is on the level", Device.dwFrame, Device.dwTimeGlobal, I->name_replace(), I->ID));
        }
        void try_online() { I->try_switch_online(); }
        bool online() const { return I->m_bOnline; }
        bool keep_data() const { return I->keep_saved_data_anyway(); }
        void clear_data() { I->client_data.clear(); }
    } operations{*this, I};
    alife_switch_lifecycle::manager_online(operations);
    STOP_PROFILE
}

void CALifeSwitchManager::try_switch_offline(CSE_ALifeDynamicObject* I)
{
    START_PROFILE("ALife/switch/try_switch_offline")
    // checking if the object is not attached
    if (0xffff != I->ID_Parent)
    {
#ifdef DEBUG
        // checking if parent is online too
        CSE_ALifeCreatureAbstract* l_tpALifeCreatureAbstract = smart_cast<CSE_ALifeCreatureAbstract*>(objects().object(I->ID_Parent));
        if (l_tpALifeCreatureAbstract && (l_tpALifeCreatureAbstract->fHealth < EPS_L))
            Msg("! uncontrolled situation [%d][%d][%s][%f]", I->ID, I->ID_Parent, l_tpALifeCreatureAbstract->name_replace(), l_tpALifeCreatureAbstract->fHealth);

        VERIFY2(!smart_cast<CSE_ALifeCreatureAbstract*>(objects().object(I->ID_Parent)) ||
                    (smart_cast<CSE_ALifeCreatureAbstract*>(objects().object(I->ID_Parent))->fHealth >= EPS_L),
                "Parent offline, item online...");

        if (!objects().object(I->ID_Parent)->m_bOnline)
            Msg("! uncontrolled situation [%d][%d][%s][%f]", I->ID, I->ID_Parent, l_tpALifeCreatureAbstract->name_replace(), l_tpALifeCreatureAbstract->fHealth);

        VERIFY2(objects().object(I->ID_Parent)->m_bOnline, "Parent offline, item online...");
#endif
        return;
    }

    I->try_switch_offline();
    STOP_PROFILE
}

struct CALifeSwitchManager::ReconciliationOperations
{
    CALifeSwitchManager& manager;
    CSE_ALifeDynamicObject* object;
    bool redundant() const { return object->redundant(); }
    void release() { manager.release(object); }
    bool synchronize_location() { return manager.synchronize_location(object); }
    bool online() const { return object->m_bOnline; }
    // Preserve manager checks and virtual group/object switching behavior.
    void try_switch_online() { manager.try_switch_online(object); }
    void try_switch_offline() { manager.try_switch_offline(object); }
};

void CALifeSwitchManager::switch_object(CSE_ALifeDynamicObject* I)
{
    if (alife_service_trace::visits_enabled.load(std::memory_order_relaxed))
        alife_service_trace::object("visit", I);
    ReconciliationOperations operations{*this, I};
    if (m_reconciliation.sampled)
    {
        alife_diagnostics::ReconciliationTiming<CTimer> timing(m_reconciliation.stages);
        alife_switch_lifecycle::reconcile_object(operations, timing);
    }
    else
    {
        alife_switch_lifecycle::Unobserved observer;
        alife_switch_lifecycle::reconcile_object(operations, observer);
    }
}

void CALifeSwitchManager::begin_reconciliation()
{
    m_reconciliation.begin();
}

void CALifeSwitchManager::finish_reconciliation(double elapsed_ms, double budget_ms, u32 visited)
{
    m_reconciliation.finish(Device.dwTimeGlobal, Device.dwFrame, elapsed_ms, budget_ms, visited,
        [](const char* format, auto... values) { Msg(format, values...); },
        [](std::uint32_t frame) { TracyPlot("ALife/engine frame", int64_t(frame)); });
}
