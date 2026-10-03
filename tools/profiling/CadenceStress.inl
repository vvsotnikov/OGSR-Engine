// Temporary opt-in stress probe, packaged separately from the experiment build.
#include "alife_simulator.h"
#include "alife_object_registry.h"
#include "level_graph.h"
#include "game_graph.h"
#include "game_level_cross_table.h"
#include "xrserver.h"
#include "game_sv_single.h"
#include "xrServer_Objects_ALife_Monsters.h"
#include "ai/stalker/ai_stalker.h"
#include "script_game_object.h"
#include "memory_manager.h"
#include "enemy_manager.h"
#include "../xr_3da/SchedulerProbe.h"
#include <fstream>

static void ConfigureProbeCombat(const xr_vector<u16>& ids)
{
    xr_vector<CAI_Stalker*> fighters;
    for (u32 i = 0; i < ids.size(); ++i)
    {
        auto* npc = smart_cast<CAI_Stalker*>(Level().Objects.net_Find(ids[i]));
        R_ASSERT(npc && npc->g_Alive());
        npc->lua_game_object()->SetCharacterCommunity(i % 2 ? "bandit" : "stalker", 0, 20 + i % 2);
        fighters.push_back(npc);
    }
    for (auto* npc : fighters)
    {
        npc->lua_game_object()->SetRelation(ALife::eRelationTypeFriend, Actor()->lua_game_object());
        Actor()->lua_game_object()->SetRelation(ALife::eRelationTypeFriend, npc->lua_game_object());
        for (u32 i = 0; i < Level().Objects.o_count(); ++i)
            if (auto* other = smart_cast<CAI_Stalker*>(Level().Objects.o_get_by_iterator(i)); other && other != npc)
            {
                npc->lua_game_object()->SetRelation(ALife::eRelationTypeFriend, other->lua_game_object());
                other->lua_game_object()->SetRelation(ALife::eRelationTypeFriend, npc->lua_game_object());
            }
    }
    for (u32 i = 0; i < fighters.size(); ++i)
        for (u32 j = 0; j < fighters.size(); ++j)
            if (i % 2 != j % 2)
                fighters[i]->lua_game_object()->SetRelation(ALife::eRelationTypeEnemy, fighters[j]->lua_game_object());
    Msg("[cadence combat] begin game_ms=%u fighters=%u", Device.dwTimeGlobal, u32(fighters.size()));
}

static void RunPopulationStress()
{
    const char* option = strstr(Core.Params, "-alife_stress ");
    if (!option || !ai().get_alife() || !g_actor)
        return;
    static unsigned requested = 0;
    static unsigned stage = 0;
    static ULONGLONG deadline = 0;
    static std::ofstream frames;
    static xr_vector<u16> ids;
    static ULONGLONG last_inventory = 0;
    static const bool combat = strstr(Core.Params, "-alife_combat") != nullptr;
    static std::ofstream cohort;
    const ULONGLONG now = GetTickCount64();
    if (!stage)
    {
        sscanf(option, "-alife_stress %u", &requested);
        R_ASSERT(requested <= 400);
        R_ASSERT(!combat || requested == 20);
        cohort = CadenceProbe::Open("cadence-cohort.csv", "game_ms,stage,id,alive,health,x,y,z,enemy");
        string_path path;
        FS.update_path(path, "$app_data_root$", "stress-frames.csv");
        frames.open(path);
        R_ASSERT(frames.good());
        frames << "game_ms,frame,stage,frame_ms\n";
        stage = 1;
        deadline = now + 15000;
        Msg("[stress] ready requested=%u section=stalker placement_seed=12345 spacing=3 min_actor_distance=40", requested);
    }
    frames << Device.dwTimeGlobal << ',' << Device.dwFrame << ',' << stage << ',' << Device.fTimeDeltaReal * 1000.0 << '\n';
    if (Device.Paused() || !Actor()->g_Alive())
    {
        Msg("[stress] invalid paused=%u actor_alive=%u", u32(Device.Paused()), u32(Actor()->g_Alive()));
        frames.close();
        Console->Execute("quit");
        return;
    }
    if (stage == 1 && now >= deadline)
    {
        xr_vector<Fvector> positions;
        const auto& graph = ai().level_graph();
        const u32 nodes = graph.header().vertex_count();
        u32 random = 12345;
        Fvector center;
        bool have_center = false;
        CTimer timer;
        timer.Start();
        for (u32 attempt = 0; ids.size() < requested && attempt < nodes * 4; ++attempt)
        {
            random = random * 1664525u + 1013904223u;
            const u32 node = random % nodes;
            if (!graph.is_accessible(node))
                continue;
            const Fvector position = graph.vertex_position(node);
            if (position.distance_to(Actor()->Position()) < 40.f)
                continue;
            if (combat)
            {
                // Fixed nav-node layout: restrict the encounter to a small area.
                if (!have_center)
                {
                    if (position.distance_to(Actor()->Position()) > 80.f) continue;
                    center = position;
                    have_center = true;
                    Msg("[cadence combat] center x=%.3f y=%.3f z=%.3f", center.x, center.y, center.z);
                }
                if (position.distance_to(center) > 14.f || _abs(position.y - center.y) > 1.f) continue;
                // Alternate two sides of the encounter instead of interleaving teams.
                if ((ids.size() % 2 == 0 && position.x > center.x - 3.f) ||
                    (ids.size() % 2 == 1 && position.x < center.x + 3.f)) continue;
            }
            bool spaced = true;
            for (const auto& previous : positions)
                if (position.distance_to(previous) < 3.f) { spaced = false; break; }
            if (!spaced)
                continue;
            const auto game_vertex = ai().cross_table().vertex(node).game_vertex_id();
            if (!ai().game_graph().valid_vertex_id(game_vertex) || ai().game_graph().vertex(game_vertex)->level_id() != graph.level_id())
                continue;
            auto* game = smart_cast<game_sv_Single*>(Level().Server->game);
            R_ASSERT(game);
            auto* object = game->alife().spawn_item("stalker", position, node, game_vertex, 0xffff);
            if (combat)
            {
                game->alife().spawn_item("wpn_ak74", position, node, game_vertex, object->ID);
                for (u32 box = 0; box < 4; ++box)
                    game->alife().spawn_item("ammo_5.45x39_fmj", position, node, game_vertex, object->ID);
            }
            ids.push_back(object->ID);
            positions.push_back(position);
            Msg("[stress spawn] id=%u node=%u graph=%u x=%.3f y=%.3f z=%.3f", u32(object->ID), node, u32(game_vertex), position.x, position.y, position.z);
        }
        Msg("[stress] spawn_complete requested=%u created=%u spawn_ms=%.3f game_ms=%u", requested, u32(ids.size()), timer.GetElapsed_sec() * 1000.f, Device.dwTimeGlobal);
        stage = 2;
        deadline = GetTickCount64() + 15000;
    }
    else if (stage == 2 && now >= deadline)
    {
        if (combat) ConfigureProbeCombat(ids);
        stage = 3;
        deadline = now + 30000;
        Msg("[stress] measure_begin game_ms=%u", Device.dwTimeGlobal);
    }
    else if (stage == 3 && now >= deadline)
    {
        Msg("[stress] measure_end game_ms=%u", Device.dwTimeGlobal);
        frames.close();
        cohort.close();
        Console->Execute("quit");
        return;
    }
    if (now - last_inventory >= 1000)
    {
        u32 retained = 0, living = 0, online = 0;
        for (const u16 id : ids)
        {
            const auto* object = ai().alife().objects().object(id, true);
            if (!object) continue;
            ++retained;
            const auto* creature = smart_cast<const CSE_ALifeCreatureAbstract*>(object);
            if (creature && creature->fHealth > 0) ++living;
            if (object->m_bOnline) ++online;
        }
        Msg("[stress population] game_ms=%u stage=%u requested=%u retained=%u living=%u online=%u", Device.dwTimeGlobal, stage, requested, retained, living, online);
        last_inventory = now;
        for (u32 i = 0; i < Level().Objects.o_count(); ++i)
            if (const auto* npc = smart_cast<const CAI_Stalker*>(Level().Objects.o_get_by_iterator(i)))
            {
                const auto* enemy = npc->memory().enemy().selected();
                const auto& pos = npc->Position();
                cohort << Device.dwTimeGlobal << ',' << stage << ',' << npc->ID() << ',' << npc->g_Alive() << ',' << npc->GetfHealth()
                       << ',' << pos.x << ',' << pos.y << ',' << pos.z << ',' << (enemy ? enemy->ID() : 0xffff) << '\n';
            }
    }
}
