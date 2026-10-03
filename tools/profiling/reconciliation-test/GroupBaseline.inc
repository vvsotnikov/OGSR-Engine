// Frozen pre-refactor reference from b6e73fac6; no Git history required.
void Baseline::try_switch_offline()
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
            // so, monster is not dead
            // checking if the object is _not_ ready to switch offline
            if (!tpGroupMember->can_switch_offline())
                continue;

            if (!tpGroupMember->can_switch_online())
                // so, it is not ready, breaking a cycle, because we can't
                // switch group offline since not all the group members are ready
                // to switch offline
                break;

            if (!I->alife().uses_distance_switching() || I->alife().graph().actor()->o_Position.distance_to(tpGroupMember->o_Position) <= I->alife().offline_distance())
                // so, it is not ready, breaking a cycle, because we can't
                // switch group offline since not all the group members are ready
                // to switch offline
                break;

            continue;
        }

        // detach object from the group
        tpGroupMember->fHealth = 0.f;
        tpGroupMember->m_bDirectControl = true;
        m_tpMembers.erase(m_tpMembers.begin() + i);
        tpGroupMember->m_bOnline = false;
        CSE_ALifeInventoryItem* item = smart_cast<CSE_ALifeInventoryItem*>(tpGroupMember);
        if (item && item->attached())
        {
            CSE_ALifeDynamicObject* object = ai().alife().objects().object(tpGroupMember->ID_Parent, true);
            if (object)
                object->detach(item);
        }
        // store the __new separate object into the registries
        I->alife().register_object(tpGroupMember);

        // and remove it from the graph point but do not remove it from the current level map
        CSE_ALifeInventoryItem* l_tpALifeInventoryItem = smart_cast<CSE_ALifeInventoryItem*>(tpGroupMember);
        if (!l_tpALifeInventoryItem || !l_tpALifeInventoryItem->attached())
            I->alife().graph().remove(tpGroupMember, tpGroupMember->m_tGraphID, false);

        tpGroupMember->m_bOnline = true;
        --m_wCount;
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
