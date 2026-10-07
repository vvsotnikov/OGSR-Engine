////////////////////////////////////////////////////////////////////////////
//	Module 		: alife_group_abstract.cpp
//	Created 	: 27.10.2005
//  Modified 	: 27.10.2005
//	Author		: Dmitriy Iassenev
//	Description : ALife group abstract class
////////////////////////////////////////////////////////////////////////////

#include "stdafx.h"
#include "alife_switch_policy.h"
#include "xrServer_Objects_ALife.h"
#include "ai_space.h"
#include "alife_simulator.h"
#include "alife_object_registry.h"
#include "xrServer_Objects_ALife_Monsters.h"
#include "alife_schedule_registry.h"
#include "alife_graph_registry.h"
#include "game_level_cross_table.h"
#include "level_graph.h"

void CSE_ALifeGroupAbstract::switch_online()
{
    CSE_ALifeDynamicObject* object = smart_cast<CSE_ALifeDynamicObject*>(this);
    VERIFY(object);

    R_ASSERT(!object->m_bOnline);
    object->m_bOnline = true;

    ALife::OBJECT_IT I = m_tpMembers.begin(), B = I;
    ALife::OBJECT_IT E = m_tpMembers.end();
    u32 N = (u32)(E - I);
    for (; I != E; ++I)
    {
        CSE_ALifeDynamicObject* J = ai().alife().objects().object(*I);
        if (m_bCreateSpawnPositions)
        {
            J->o_Position = object->o_Position;
            J->m_tNodeID = object->m_tNodeID;
            CSE_ALifeMonsterAbstract* l_tpALifeMonsterAbstract = smart_cast<CSE_ALifeMonsterAbstract*>(J);
            if (l_tpALifeMonsterAbstract)
                l_tpALifeMonsterAbstract->o_torso.yaw = angle_normalize_signed((I - B) / N * PI_MUL_2);
        }
        object->alife().add_online(J, false);
    }
    m_bCreateSpawnPositions = false;
    object->alife().scheduled().remove(object);
    object->alife().graph().remove(object, object->m_tGraphID, false);
}

void CSE_ALifeGroupAbstract::switch_offline()
{
    CSE_ALifeDynamicObject* object = smart_cast<CSE_ALifeDynamicObject*>(base());
    VERIFY(object);

    R_ASSERT(object->m_bOnline);
    object->m_bOnline = false;

    ALife::OBJECT_IT I = m_tpMembers.begin();
    ALife::OBJECT_IT E = m_tpMembers.end();
    if (I != E)
    {
        CSE_ALifeMonsterAbstract* tpGroupMember = smart_cast<CSE_ALifeMonsterAbstract*>(ai().alife().objects().object(*I));
        CSE_ALifeMonsterAbstract* tpGroup = smart_cast<CSE_ALifeMonsterAbstract*>(this);
        if (tpGroupMember && tpGroup)
        {
            tpGroup->m_fCurSpeed = tpGroup->m_fCurrentLevelGoingSpeed;
            tpGroup->o_Position = tpGroupMember->o_Position;
            u32 dwNodeID = tpGroup->m_tNodeID;
            tpGroup->m_tGraphID = ai().cross_table().vertex(dwNodeID).game_vertex_id();
            tpGroup->m_fDistanceToPoint = ai().cross_table().vertex(dwNodeID).distance();
            tpGroup->m_tNextGraphID = tpGroup->m_tGraphID;
            u16 wNeighbourCount = ai().game_graph().vertex(tpGroup->m_tGraphID)->edge_count();
            CGameGraph::const_iterator i, e;
            ai().game_graph().begin(tpGroup->m_tGraphID, i, e);
            tpGroup->m_tPrevGraphID = (*(i + ::Random.randI(0, wNeighbourCount))).vertex_id();
        }
        object->alife().remove_online(tpGroupMember, false);
        ++I;
    }
    for (; I != E; ++I)
        object->alife().remove_online(ai().alife().objects().object(*I), false);
    object->alife().scheduled().add(object);
    object->alife().graph().add(object, object->m_tGraphID, false);
}

bool CSE_ALifeGroupAbstract::synchronize_location()
{
    if (m_tpMembers.empty())
        return (true);

    CSE_ALifeDynamicObject* object = smart_cast<CSE_ALifeDynamicObject*>(base());
    VERIFY(object);

    ALife::OBJECT_VECTOR::iterator I = m_tpMembers.begin();
    ALife::OBJECT_VECTOR::iterator E = m_tpMembers.end();
    for (; I != E; ++I)
        ai().alife().objects().object(*I)->synchronize_location();

    CSE_ALifeDynamicObject& member = *ai().alife().objects().object(*I); //-V783
    object->o_Position = member.o_Position;
    object->m_tNodeID = member.m_tNodeID;

    if (object->m_tGraphID != member.m_tGraphID)
    {
        if (!object->m_bOnline)
            object->alife().graph().change(object, object->m_tGraphID, member.m_tGraphID);
        else
            object->m_tGraphID = member.m_tGraphID;
    }

    object->m_fDistance = member.m_fDistance;
    return (true);
}

void CSE_ALifeGroupAbstract::try_switch_online()
{
    CSE_ALifeDynamicObject* I = smart_cast<CSE_ALifeDynamicObject*>(base());
    VERIFY(I);

    // checking if the object is not an empty group of objects
    if (m_tpMembers.empty())
        return;

    I->try_switch_online();
}

void CSE_ALifeGroupAbstract::try_switch_offline()
{
    struct Operations
    {
        CSE_ALifeGroupAbstract& group;
        CSE_ALifeDynamicObject* object = nullptr;
        unsigned size() const { return unsigned(group.m_tpMembers.size()); }
        void bind_group() { object = smart_cast<CSE_ALifeDynamicObject*>(group.base()); VERIFY(object); }
        CSE_ALifeMonsterAbstract* monster(unsigned i) const { return smart_cast<CSE_ALifeMonsterAbstract*>(ai().alife().objects().object(group.m_tpMembers[i])); }
        bool alive(CSE_ALifeMonsterAbstract* member) const { return member->g_Alive(); }
        bool can_online(CSE_ALifeMonsterAbstract* member) const { return member->can_switch_online(); }
        bool can_offline(CSE_ALifeMonsterAbstract* member) const { return member->can_switch_offline(); }
        bool can_online() const { return object->can_switch_online(); }
        bool can_offline() const { return object->can_switch_offline(); }
        bool distance_mode() const { return object->alife().uses_distance_switching(); }
        float actor_distance(CSE_ALifeMonsterAbstract* member) const { return object->alife().graph().actor()->o_Position.distance_to(member->o_Position); }
        float offline_limit() const { return object->alife().offline_distance(); }
        void mark_dead(CSE_ALifeMonsterAbstract* member) { member->fHealth = 0.f; }
        void set_direct_control(CSE_ALifeMonsterAbstract* member) { member->m_bDirectControl = true; }
        void erase_member(unsigned i) { group.m_tpMembers.erase(group.m_tpMembers.begin() + i); }
        void set_online(CSE_ALifeMonsterAbstract* member, bool value) { member->m_bOnline = value; }
        void detach_if_attached(CSE_ALifeMonsterAbstract* member)
        {
            auto* item = smart_cast<CSE_ALifeInventoryItem*>(member);
            if (item && item->attached())
            {
                auto* parent = ai().alife().objects().object(member->ID_Parent, true);
                if (parent) parent->detach(item);
            }
        }
        void register_member(CSE_ALifeMonsterAbstract* member) { object->alife().register_object(member); }
        void remove_graph_if_unattached(CSE_ALifeMonsterAbstract* member)
        {
            auto* item = smart_cast<CSE_ALifeInventoryItem*>(member);
            if (!item || !item->attached()) object->alife().graph().remove(member, member->m_tGraphID, false);
        }
        void decrement_count() { --group.m_wCount; }
        void switch_offline() { object->alife().switch_offline(object); }
    } operations{*this};
    alife_switch_policy::legacy_group_offline(operations);
}

bool CSE_ALifeGroupAbstract::redundant() const { return (m_tpMembers.empty()); }
