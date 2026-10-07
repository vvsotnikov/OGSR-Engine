////////////////////////////////////////////////////////////////////////////
//	Module 		: alife_group_registry.cpp
//	Created 	: 28.10.2005
//  Modified 	: 28.10.2005
//	Author		: Dmitriy Iassenev
//	Description : ALife group registry
////////////////////////////////////////////////////////////////////////////

#include "stdafx.h"
#include "alife_group_registry.h"
#include "xrServer_Objects_ALife_Monsters.h"
#include "alife_simulator.h"
#include "ai_space.h"
#include "alife_object_registry.h"
#include "alife_graph_registry.h"
#include "alife_schedule_registry.h"

CALifeGroupRegistry::~CALifeGroupRegistry() {}

void CALifeGroupRegistry::add(CSE_ALifeDynamicObject* object)
{
    if (auto* legacy = smart_cast<CSE_ALifeGroupAbstract*>(object))
    {
        VERIFY(m_legacy_objects.find(object->ID) == m_legacy_objects.end());
        m_legacy_objects.emplace(object->ID, legacy);
        return;
    }
    CSE_ALifeOnlineOfflineGroup* group = smart_cast<CSE_ALifeOnlineOfflineGroup*>(object);
    if (!group)
        return;

    VERIFY(objects().find(group->ID) == objects().end());
    m_objects.insert(std::make_pair(group->ID, group));
}

void CALifeGroupRegistry::remove(CSE_ALifeDynamicObject* object)
{
    if (auto* legacy = smart_cast<CSE_ALifeGroupAbstract*>(object))
    {
        m_legacy_objects.erase(object->ID);
        // Removing an owner must leave surviving members independently managed.
        // Whole-simulator teardown destroys registries directly and never calls here.
        for (const auto id : legacy->m_tpMembers)
        {
            auto* member = ai().alife().objects().object(id);
            member->m_bDirectControl = true;
            if (member->m_bOnline)
                object->alife().graph().level().add(member);
            else
            {
                object->alife().graph().update(member);
                object->alife().scheduled().add(member);
            }
        }
        legacy->m_tpMembers.clear();
        legacy->m_wCount = 0;
        return;
    }
    if (!object->m_bDirectControl)
    {
        // Remove membership before the released ID can be reused. Only legacy
        // owners are searched, and only on destruction, not on every switch pass.
        for (auto& entry : m_legacy_objects)
        {
            auto& group = *entry.second;
            const auto member = std::find(group.m_tpMembers.begin(), group.m_tpMembers.end(), object->ID);
            if (member == group.m_tpMembers.end()) continue;
            group.m_tpMembers.erase(member);
            VERIFY(group.m_wCount);
            --group.m_wCount;
        }
    }
    CSE_ALifeOnlineOfflineGroup* group = smart_cast<CSE_ALifeOnlineOfflineGroup*>(object);
    if (!group)
        return;

    OBJECTS::iterator I = m_objects.find(group->ID);
    VERIFY(I != m_objects.end());
    m_objects.erase(I);
}

CALifeGroupRegistry::OBJECT& CALifeGroupRegistry::object(const ALife::_OBJECT_ID& id) const
{
    OBJECTS::const_iterator I = objects().find(id);
    VERIFY(I != objects().end());
    return (*(*I).second);
}

void CALifeGroupRegistry::on_after_game_load()
{
    OBJECTS::iterator I = m_objects.begin();
    OBJECTS::iterator E = m_objects.end();
    for (; I != E; ++I)
        (*I).second->on_after_game_load();
}
