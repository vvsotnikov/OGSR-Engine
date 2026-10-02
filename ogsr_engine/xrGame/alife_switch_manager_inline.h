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
    m_switch_distance = pSettings->r_float(section, "switch_distance");
    m_switch_factor = pSettings->r_float(section, "switch_factor");
    set_switch_distance(m_switch_distance);
    // Launch-only experiment: retain script eligibility and parent/group handling.
    m_whole_map_online = strstr(Core.Params, "-alife_whole_map") != nullptr;
    m_alife_metrics = strstr(Core.Params, "-alife_metrics") != nullptr;
    Msg("* ALife policy: %s; metrics: %s; configured switch distance: %.1f",
        m_whole_map_online ? "whole current map" : "distance", m_alife_metrics ? "on" : "off", m_switch_distance);
}

// Only distance gates change. The level registry still limits switching to the
// loaded map; explicit cannot-online flags continue to take precedence.
IC float CALifeSwitchManager::online_distance() const { return m_whole_map_online ? flt_max : m_online_distance; }

IC float CALifeSwitchManager::offline_distance() const { return m_whole_map_online ? flt_max : m_offline_distance; }

IC float CALifeSwitchManager::switch_distance() const { return (m_switch_distance); }

IC void CALifeSwitchManager::set_switch_distance(float switch_distance)
{
    m_switch_distance = switch_distance;
    m_online_distance = m_switch_distance * (1.f - m_switch_factor);
    m_offline_distance = m_switch_distance * (1.f + m_switch_factor);
}

IC void CALifeSwitchManager::set_switch_factor(float switch_factor)
{
    m_switch_factor = switch_factor;
    set_switch_distance(switch_distance());
}
