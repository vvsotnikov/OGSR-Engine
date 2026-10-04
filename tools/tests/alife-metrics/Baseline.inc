// Frozen pre-refactor reference from d89893ca1; no Git history required.
void Baseline::switch_object(CSE_ALifeDynamicObject* I)
{
    if (I->redundant())
    {
        release(I);
        return;
    }

    if (!synchronize_location(I))
        return;

    if (I->m_bOnline)
        try_switch_offline(I);
    else
        try_switch_online(I);

    if (I->redundant())
        release(I);
}
