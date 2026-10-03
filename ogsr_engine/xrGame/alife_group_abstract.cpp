////////////////////////////////////////////////////////////////////////////
//	Module 		: alife_group_abstract.cpp
//	Created 	: 27.10.2005
//  Modified 	: 27.10.2005
//	Author		: Dmitriy Iassenev
//	Description : ALife group abstract class
////////////////////////////////////////////////////////////////////////////

#include "stdafx.h"
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

namespace
{
// This is the legacy scan's early-exit policy, not the final group decision.
bool stops_group_offline_scan(CSE_ALifeMonsterAbstract* member, CSE_ALifeDynamicObject* group)
{
    if (!member->can_switch_offline())
        return false;
    if (!member->can_switch_online())
        return true;
    return !group->alife().uses_distance_switching() ||
        group->alife().graph().actor()->o_Position.distance_to(member->o_Position) <= group->alife().offline_distance();
}

void detach_dead_group_member(CSE_ALifeGroupAbstract& group, u32 index, CSE_ALifeMonsterAbstract* member, CSE_ALifeDynamicObject* object)
{
    member->fHealth = 0.f;
    member->m_bDirectControl = true;
    group.m_tpMembers.erase(group.m_tpMembers.begin() + index);
    member->m_bOnline = false;
    CSE_ALifeInventoryItem* item = smart_cast<CSE_ALifeInventoryItem*>(member);
    if (item && item->attached())
    {
        CSE_ALifeDynamicObject* parent = ai().alife().objects().object(member->ID_Parent, true);
        if (parent)
            parent->detach(item);
    }
    // Register the separate object, then remove its graph-point membership
    // while retaining current-level membership. Recheck attachment after registration.
    object->alife().register_object(member);
    CSE_ALifeInventoryItem* inventory_item = smart_cast<CSE_ALifeInventoryItem*>(member);
    if (!inventory_item || !inventory_item->attached())
        object->alife().graph().remove(member, member->m_tGraphID, false);
    member->m_bOnline = true;
    --group.m_wCount;
}
}

void CSE_ALifeGroupAbstract::try_switch_offline()
{
    // checking if group is not empty
    if (m_tpMembers.empty())
        return;

    // so, we have a group of objects
    // therefore check all the group members if they are ready to switch offline

    CSE_ALifeDynamicObject* I = smart_cast<CSE_ALifeDynamicObject*>(base());
    VERIFY(I);

    u32 i = 0, N = m_tpMembers.size();

    // iterating on group members
    for (; i < N; ++i)
    {
        // casting group member to the abstract monster to get access to the Health property
        CSE_ALifeMonsterAbstract* tpGroupMember = smart_cast<CSE_ALifeMonsterAbstract*>(ai().alife().objects().object(m_tpMembers[i]));
        if (!tpGroupMember)
            continue;

        // check if monster is not dead
        if (tpGroupMember->g_Alive())
        {
            if (stops_group_offline_scan(tpGroupMember, I))
                break;

            continue;
        }

        // Keep cleanup in traversal order: an earlier live member may stop the
        // scan before this member. A separate full cleanup pass changes behavior.
        detach_dead_group_member(*this, i, tpGroupMember, I);
        --i;
        --N;
    }

    // checking if group is not empty
    if (m_tpMembers.empty())
        return;

    if (!I->can_switch_offline())
        return;

    if (I->can_switch_online() || (i == N))
        I->alife().switch_offline(I);
}

bool CSE_ALifeGroupAbstract::redundant() const { return (m_tpMembers.empty()); }
