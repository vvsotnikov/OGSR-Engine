////////////////////////////////////////////////////////////////////////////
//	Module 		: alife_dynamic_object.cpp
//	Created 	: 27.10.2005
//  Modified 	: 27.10.2005
//	Author		: Dmitriy Iassenev
//	Description : ALife dynamic object class
////////////////////////////////////////////////////////////////////////////

#include "stdafx.h"
#include "alife_service_trace.h"
#include "alife_switch_policy.h"
#include "xrServer_Objects_ALife.h"
#include "alife_simulator.h"
#include "alife_schedule_registry.h"
#include "alife_graph_registry.h"
#include "alife_object_registry.h"
#include "level_graph.h"
#include "game_level_cross_table.h"
#include "game_graph.h"
#include "xrServer.h"

void CSE_ALifeDynamicObject::on_spawn()
{
#ifdef DEBUG
//	Msg			("[LSS] spawning object [%d][%d][%s][%s]",ID,ID_Parent,name(),name_replace());
#endif
}

void CSE_ALifeDynamicObject::on_register()
{
    CSE_ALifeObject* object = this;
    while (object->ID_Parent != ALife::_OBJECT_ID(-1))
    {
        object = ai().alife().objects().object(object->ID_Parent);
        VERIFY(object);
    }

    if (!alife().graph().level().object(object->ID, true) && !keep_saved_data_anyway())
        client_data.clear();
}

void CSE_ALifeDynamicObject::on_before_register() {}

#include "level.h"
#include "map_manager.h"

void CSE_ALifeDynamicObject::on_unregister() { Level().MapManager().RemoveMapLocationByObjectID(ID); }

void CSE_ALifeDynamicObject::switch_online()
{
    R_ASSERT(!m_bOnline);
    m_bOnline = true;
    alife().add_online(this);
}

void CSE_ALifeDynamicObject::switch_offline()
{
    R_ASSERT(m_bOnline);
    m_bOnline = false;
    alife().remove_online(this);
#ifdef DEBUG
    if (!client_data.empty())
        Msg("CSE_ALifeDynamicObject::switch_offline: client_data is cleared for [%d][%s]", ID, name_replace());
#endif // DEBUG
    if (!keep_saved_data_anyway())
        client_data.clear();
}

void CSE_ALifeDynamicObject::add_online(const bool& update_registries)
{
    if (!update_registries)
        return;

    alife().scheduled().remove(this);
    alife().graph().remove(this, m_tGraphID, false);
}

void CSE_ALifeDynamicObject::add_offline(const xr_vector<ALife::_OBJECT_ID>& saved_children, const bool& update_registries)
{
    if (!update_registries)
        return;

    alife().scheduled().add(this);
    alife().graph().add(this, m_tGraphID, false);
}

bool CSE_ALifeDynamicObject::synchronize_location()
{
    if (!ai().level_graph().valid_vertex_position(o_Position) || ai().level_graph().inside(ai().level_graph().vertex(m_tNodeID), o_Position))
        return (true);

    m_tNodeID = ai().level_graph().vertex_id(m_tNodeID, o_Position);

    GameGraph::_GRAPH_ID tGraphID = ai().cross_table().vertex(m_tNodeID).game_vertex_id();
    if (tGraphID != m_tGraphID)
    {
        if (!m_bOnline)
        {
            Fvector position = o_Position;
            u32 level_vertex_id = m_tNodeID;
            alife().graph().change(this, m_tGraphID, tGraphID);
            if (ai().level_graph().inside(ai().level_graph().vertex(level_vertex_id), position))
            {
                level_vertex_id = m_tNodeID;
                o_Position = position;
            }
        }
        else
        {
            VERIFY(ai().game_graph().vertex(tGraphID)->level_id() == alife().graph().level().level_id());
            m_tGraphID = tGraphID;
        }
    }

    m_fDistance = ai().cross_table().vertex(m_tNodeID).distance();

    return (true);
}

namespace
{
struct DynamicSwitchOperations
{
    CSE_ALifeDynamicObject& object;
    CSE_ALifeSchedulable* schedule_object = nullptr;
    bool schedulable()
    {
        schedule_object = smart_cast<CSE_ALifeSchedulable*>(&object);
        return schedule_object != nullptr;
    }
    bool needs_update() { return schedule_object->need_update(&object); }
    bool scheduled() const { return object.alife().scheduled().object(object.ID, true) != nullptr; }
    void schedule() { object.alife().scheduled().add(&object); }
    void unschedule() { object.alife().scheduled().remove(&object); }
    bool can_online() const { return object.can_switch_online(); }
    bool can_offline() const { return object.can_switch_offline(); }
    bool distance_mode() const { return object.alife().uses_distance_switching(); }
    float actor_distance() const { return object.alife().graph().actor()->o_Position.distance_to(object.o_Position); }
    float online_limit() const { return object.alife().online_distance(); }
    float offline_limit() const { return object.alife().offline_distance(); }
    bool keep_data() const { return object.keep_saved_data_anyway(); }
    void clear_data() { object.client_data.clear(); }
    void report_rejection(bool distance) const
    {
        alife_service_trace::event(distance ? "distance_rejected" : "permission_rejected", object.ID);
#ifdef DEBUG
        if (!object.client_data.empty())
        {
            if (distance)
                Msg("CSE_ALifeDynamicObject::try_switch_online2: client_data is cleared for [%d][%s]", object.ID, object.name_replace());
            else
                Msg("CSE_ALifeDynamicObject::try_switch_online: client_data is cleared for [%d][%s]", object.ID, object.name_replace());
        }
#endif
    }
    void switch_online() { alife_service_trace::event("eligible_observed", object.ID); object.alife().switch_online(&object); }
    void switch_offline() { object.alife().switch_offline(&object); }
};
}

void CSE_ALifeDynamicObject::try_switch_online()
{
    DynamicSwitchOperations operations{*this};
    alife_switch_policy::dynamic_online(operations);
}

void CSE_ALifeDynamicObject::try_switch_offline()
{
    DynamicSwitchOperations operations{*this};
    alife_switch_policy::dynamic_offline(operations);
}

bool CSE_ALifeDynamicObject::redundant() const { return (false); }
