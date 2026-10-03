// Frozen pre-refactor reference from 0924e934b; no Git history required.
void Baseline::try_switch_online()
{
    CSE_ALifeSchedulable* schedulable = smart_cast<CSE_ALifeSchedulable*>(this);
    // checking if the abstract monster has just died
    if (schedulable)
    {
        if (!schedulable->need_update(this))
        {
            if (alife().scheduled().object(ID, true))
                alife().scheduled().remove(this);
        }
        else if (!alife().scheduled().object(ID, true))
            alife().scheduled().add(this);
    }

    if (!can_switch_online())
    {
#ifdef DEBUG
        if (!client_data.empty())
            Msg("CSE_ALifeDynamicObject::try_switch_online: client_data is cleared for [%d][%s]", ID, name_replace());
#endif // DEBUG
        if (!keep_saved_data_anyway())
            client_data.clear();
        return;
    }

    if (!can_switch_offline())
    {
        alife().switch_online(this);
        return;
    }

    if (alife().uses_distance_switching() && alife().graph().actor()->o_Position.distance_to(o_Position) > alife().online_distance())
    {
#ifdef DEBUG
        if (!client_data.empty())
            Msg("CSE_ALifeDynamicObject::try_switch_online2: client_data is cleared for [%d][%s]", ID, name_replace());
#endif // DEBUG
        if (!keep_saved_data_anyway())
            client_data.clear();
        return;
    }

    alife().switch_online(this);
}
void Baseline::try_switch_offline()
{
    if (!can_switch_offline())
        return;

    if (!can_switch_online())
    {
        alife().switch_offline(this);
        return;
    }

    if (!alife().uses_distance_switching() || alife().graph().actor()->o_Position.distance_to(o_Position) <= alife().offline_distance())
        return;

    alife().switch_offline(this);
}
