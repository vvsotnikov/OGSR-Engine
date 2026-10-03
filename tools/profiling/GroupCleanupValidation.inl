// Disposable distance-mode group probe; never compiled into the normal package.
#include "alife_simulator.h"
#include "xrserver.h"
#include "game_sv_single.h"
#include "alife_object_registry.h"
#include "alife_graph_registry.h"
#include "level_graph.h"
#include "game_graph.h"
#include "game_level_cross_table.h"
#include "xrServer_Objects_ALife_Monsters.h"
#include <fstream>

static void RunGroupCleanupValidation()
{
    if (!strstr(Core.Params, "-group_cleanup_validation") || !ai().get_alife() || !g_actor || Device.dwPrecacheFrame)
        return;
    static unsigned stage = 0;
    static u16 group_id = 0xffff, member_id = 0xffff;
    static ULONGLONG deadline = 0;
    auto* game = smart_cast<game_sv_Single*>(Level().Server->game);
    R_ASSERT(game);
    auto& sim = game->alife();
    R_ASSERT(sim.uses_distance_switching());
    string_path ids_path;
    FS.update_path(ids_path, "$app_data_root$", "group-ids.txt");
    if (!stage)
    {
        Console->Execute("g_god on");
        sim.set_switch_distance(1.f);
        if (strstr(Core.Params, "-group_cleanup_reload"))
        {
            unsigned g, m;
            std::ifstream input(ids_path);
            R_ASSERT(bool(input >> g >> m));
            group_id = u16(g); member_id = u16(m);
            auto* group = smart_cast<CSE_ALifeOnlineOfflineGroup*>(ai().alife().objects().object(group_id));
            R_ASSERT(group && group->member(member_id, true));
            R_ASSERT(!group->m_bOnline && group->client_data.empty());
            Msg("[group cleanup] restored group=%u member=%u offline=1 data_empty=1", g, m);
            stage = 4;
        }
        else
        {
            const auto& graph = ai().level_graph();
            u32 node = 0;
            for (; node < graph.header().vertex_count(); ++node)
            {
                if (graph.vertex_position(node).distance_to(Actor()->Position()) < 50.f) continue;
                auto game_vertex = ai().cross_table().vertex(node).game_vertex_id();
                if (ai().game_graph().valid_vertex_id(game_vertex) && ai().game_graph().vertex(game_vertex)->level_id() == graph.level_id()) break;
            }
            R_ASSERT(node < graph.header().vertex_count());
            auto game_vertex = ai().cross_table().vertex(node).game_vertex_id();
            auto* group = smart_cast<CSE_ALifeOnlineOfflineGroup*>(sim.spawn_item("validation_online_group", graph.vertex_position(node), node, game_vertex, 0xffff));
            R_ASSERT(group && !group->keep_saved_data_anyway());
            group_id = group->ID;
            group->client_data.push_back(0x5a);
            sim.try_switch_online(group);
            R_ASSERT(!group->m_bOnline && group->client_data.empty());
            Msg("[group cleanup] empty_group_cleared");
            auto* member = smart_cast<CSE_ALifeHumanStalker*>(sim.spawn_item("stalker", graph.vertex_position(node), node, game_vertex, 0xffff));
            R_ASSERT(member);
            member_id = member->ID;
            group->register_member(member_id);
            group->client_data.push_back(0x5a);
            sim.try_switch_online(group);
            R_ASSERT(group->can_switch_online() && !group->m_bOnline && group->client_data.empty());
            Msg("[group cleanup] far_group_cleared group=%u member=%u", u32(group_id), u32(member_id));
            std::ofstream output(ids_path);
            output << unsigned(group_id) << ' ' << unsigned(member_id);
            output.close();
            sim.set_switch_distance(10000.f);
            sim.try_switch_online(group);
            R_ASSERT(group->m_bOnline);
            stage = 1;
        }
        deadline = GetTickCount64() + 5000;
        return;
    }
    if (GetTickCount64() < deadline) return;
    auto* group = smart_cast<CSE_ALifeOnlineOfflineGroup*>(ai().alife().objects().object(group_id));
    R_ASSERT(group && group->member(member_id, true));
    if (stage == 1)
    {
        R_ASSERT(group->m_bOnline && Level().Objects.net_Find(member_id));
        Msg("[group cleanup] group_online member_client=1");
        sim.set_switch_distance(1.f);
        sim.try_switch_offline(group);
        R_ASSERT(!group->m_bOnline);
        stage = 2;
        deadline = GetTickCount64() + 5000;
    }
    else if (stage == 2 || stage == 4)
    {
        R_ASSERT(!group->m_bOnline && !Level().Objects.net_Find(member_id));
        group->client_data.push_back(0x5a);
        sim.try_switch_online(group);
        R_ASSERT(group->client_data.empty());
        Console->Execute(stage == 2 ? "save group_validation" : "save group_reloaded");
        Msg("[group cleanup] complete mode=%s", stage == 2 ? "save" : "reload");
        // Preserve the group in the save, then detach the synthetic member before
        // registry teardown (which can destroy the group before its member).
        group->unregister_member(member_id);
        stage = 5;
        Console->Execute("quit");
    }
}
