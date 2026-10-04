////////////////////////////////////////////////////////////////////////////
//	Module 		: alife_switch_manager_inline.h
//	Created 	: 25.12.2002
//  Modified 	: 12.05.2004
//	Author		: Dmitriy Iassenev
//	Description : ALife Simulator switch manager inline functions
////////////////////////////////////////////////////////////////////////////

#pragma once

IC CALifeSwitchManager::CALifeSwitchManager(xrServer* server, LPCSTR section) : inherited(server, section)
{
    m_alife_metrics = strstr(Core.Params, "-alife_metrics") != nullptr;
    m_alife_diagnostics = strstr(Core.Params, "-alife_diagnostics") != nullptr;
    m_reconcile_metrics = strstr(Core.Params, "-alife_reconcile_metrics") != nullptr;
    if (m_reconcile_metrics)
        Msg("* ALife reconciliation timing: update totals; stage sampling every %u updates", alife_diagnostics::Reconciliation::stage_cadence);

    if (m_alife_diagnostics && !m_alife_metrics)
        Msg("! -alife_diagnostics requires -alife_metrics");
    m_switch_distance = pSettings->r_float(section, "switch_distance");
    m_switch_factor = pSettings->r_float(section, "switch_factor");
    set_switch_distance(m_switch_distance);
    m_whole_map_online = strstr(Core.Params, "-alife_whole_map") != nullptr;
    if (m_whole_map_online)
        Msg("* ALife policy: whole-map; switch_distance remains configured but does not control switching");
}

IC bool CALifeSwitchManager::uses_distance_switching() const { return !m_whole_map_online; }

IC float CALifeSwitchManager::online_distance() const { return (m_online_distance); }

IC float CALifeSwitchManager::offline_distance() const { return (m_offline_distance); }

IC float CALifeSwitchManager::switch_distance() const { return (m_switch_distance); }

IC void CALifeSwitchManager::set_switch_distance(float switch_distance)
{
    if (m_whole_map_online && !m_distance_override_reported)
    {
        Msg("* ALife whole-map policy: switch distance/factor changes are stored but do not control switching");
        m_distance_override_reported = true;
    }
    m_switch_distance = switch_distance;
    m_online_distance = m_switch_distance * (1.f - m_switch_factor);
    m_offline_distance = m_switch_distance * (1.f + m_switch_factor);
}

IC void CALifeSwitchManager::set_switch_factor(float switch_factor)
{
    m_switch_factor = switch_factor;
    set_switch_distance(switch_distance());
}
