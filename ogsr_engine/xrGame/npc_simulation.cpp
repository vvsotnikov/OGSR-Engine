#include "stdafx.h"
#include "npc_simulation.h"
#include "alife_simulator.h"
#include "alife_object_registry.h"
#include "alife_graph_registry.h"
#include "alife_human_brain.h"
#include "alife_monster_movement_manager.h"
#include "alife_monster_detail_path_manager.h"
#include "xrServer_Objects_ALife_Monsters.h"
#include "xrServer_Objects_ALife_Items.h"
#include "ai/stalker/ai_stalker.h"
#include "ai_object_location.h"
#include "stalker_movement_manager.h"
#include "restricted_object.h"
#include "movement_manager_space.h"
#include "ai_space.h"
#include "level.h"
#include "game_graph.h"
#include "level_graph.h"
#include "xrMessages.h"

namespace
{
constexpr u32 planner_chunk = 0x4e504331; // NPC1; optional root chunk, independent of legacy registry order.
NpcLocation location(const CSE_ALifeDynamicObject& object)
{
    return {object.m_tGraphID, object.m_tNodeID, ai().game_graph().vertex(object.m_tGraphID)->level_id(), {object.o_Position.x, object.o_Position.y, object.o_Position.z}};
}
NpcLocation navigation_location(const CSE_ALifeDynamicObject& object)
{
    auto result = location(object);
    Fvector point = object.o_Position;
    if (!ai().level_graph().inside(object.m_tNodeID, point)) point = ai().level_graph().vertex_position(object.m_tNodeID);
    point.y = ai().level_graph().vertex_plane_y(object.m_tNodeID, point.x, point.z);
    result.position[0] = point.x; result.position[1] = point.y; result.position[2] = point.z;
    return result;
}
}

CNpcSimulation::~CNpcSimulation()
{
    for (auto& [_, entry] : m_entries) npc_plan_destroy(entry.plan);
}

const CALifeObjectRegistry& CNpcSimulation::objects() const
{
    return static_cast<const CALifeSimulatorBase&>(m_alife).objects();
}

CNpcSimulation::Entry* CNpcSimulation::find(CSE_ALifeMonsterAbstract* object)
{
    if (m_entries.empty()) return nullptr;
    auto human = smart_cast<CSE_ALifeHumanAbstract*>(object);
    auto found = m_entries.find(human);
    return found == m_entries.end() ? nullptr : &found->second;
}

bool CNpcSimulation::owns(CSE_ALifeMonsterAbstract* object) const
{
    return !m_entries.empty() && m_entries.find(smart_cast<CSE_ALifeHumanAbstract*>(object)) != m_entries.end();
}

bool CNpcSimulation::owns(u16 id) const
{
    if (m_entries.empty()) return false;
    return owns(smart_cast<CSE_ALifeMonsterAbstract*>(objects().object(id, true)));
}

CNpcSimulation* CNpcSimulation::active()
{
    auto alife = ai().get_alife();
    return alife && alife->initialized() && !alife->is_unloading() ? &alife->npc_simulation() : nullptr;
}

bool CNpcSimulation::configured(LPCSTR section)
{
    return pSettings->line_exist(section, "npc_planner") && !xr_strcmp(pSettings->r_string(section, "npc_planner"), "supply_trip");
}

bool CNpcSimulation::enroll(u16 npc_id, u16 supply_id)
{
    auto npc = smart_cast<CSE_ALifeHumanAbstract*>(objects().object(npc_id, true));
    auto supply = objects().object(supply_id, true);
    if (!npc || !supply || !smart_cast<CSE_ALifeInventoryItem*>(supply) || supply->ID_Parent != 0xffff ||
        npc->fHealth <= 0 || npc->m_story_id != ALife::_STORY_ID(-1) || npc->m_group_id != 0xffff ||
        npc->m_smart_terrain_id != 0xffff || owns(npc) || m_next_identity == u64(-1)) return false;
    if (!configured(npc->name())) return false;
    if (!ai().game_graph().valid_vertex_id(npc->m_tGraphID) || !ai().game_graph().valid_vertex_id(supply->m_tGraphID)) return false;
    if (npc->m_bOnline)
    {
        auto client = smart_cast<CAI_Stalker*>(Level().Objects.net_Find(npc_id));
        if (!client || client->GetScriptControl()) return false;
    }
    if (!ai().get_level_graph() ||
        ai().game_graph().vertex(npc->m_tGraphID)->level_id() != m_alife.graph().level().level_id() ||
        ai().game_graph().vertex(supply->m_tGraphID)->level_id() != m_alife.graph().level().level_id() ||
        !ai().level_graph().valid_vertex_id(npc->m_tNodeID) || !ai().level_graph().valid_vertex_id(supply->m_tNodeID)) return false;
    const auto home = navigation_location(*npc), source = navigation_location(*supply);
    NpcPlan* plan = npc_plan_create(m_next_identity, &home, &source);
    if (!plan) return false;
    Msg("[npc trip] enroll identity=%llu npc=%u supply=%u", m_next_identity, npc_id, supply_id);
    ++m_next_identity;
    m_entries.emplace(npc, Entry{npc, supply, plan});
    return true;
}

NpcDecision CNpcSimulation::observe(Entry& entry, const Fvector& here, u32 graph, bool interrupted, bool alive, bool blocked)
{
    NpcDecision before{}, after{};
    R_ASSERT(npc_plan_status(entry.plan, &before));
    NpcObservation input{};
    input.current = {graph, entry.npc->m_tNodeID, ai().game_graph().vertex(GameGraph::_GRAPH_ID(graph))->level_id(), {here.x, here.y, here.z}};
    input.interrupted = interrupted;
    input.alive = alive;
    input.path_blocked = blocked;
    input.pickup_pending = entry.pickup_command == before.command;
    input.elapsed_ms = entry.observed ? Device.dwTimeGlobal - entry.last_observation : 0;
    entry.observed = true;
    entry.last_observation = Device.dwTimeGlobal;
    if (entry.supply)
    {
        input.supply = entry.supply->ID_Parent == entry.npc->ID ? 2 : entry.supply->ID_Parent == u16(-1) ? 1 : 3;
        input.supply_location = location(*entry.supply);
        input.representation_ready = entry.supply->m_bOnline == entry.npc->m_bOnline;
    }
    // World facts are distinct from knowledge: Rust decides what can be learned
    // at the remembered destination and owns arrival, waiting and failure policy.
    R_ASSERT(npc_plan_step(entry.plan, &input, &after));
    if (before.phase != after.phase || entry.interrupted != interrupted)
        Msg("[npc trip] identity=%llu npc=%u command=%llu phase=%u interrupted=%u online=%u", after.identity,
            entry.npc->ID, after.command, after.phase, after.interrupted, u32(entry.npc->m_bOnline));
    entry.interrupted = interrupted;
    return after;
}

void CNpcSimulation::collect(Entry& entry, CAI_Stalker* client, u64 command)
{
    if (entry.pickup_command == command || !entry.supply || entry.supply->ID_Parent != 0xffff ||
        entry.npc->m_bOnline != entry.supply->m_bOnline) return;
    entry.pickup_command = command;
    if (client)
    {
        NET_Packet packet;
        CGameObject::u_EventGen(packet, GE_OWNERSHIP_TAKE, entry.npc->ID);
        packet.w_u16(entry.supply->ID);
        CGameObject::u_EventSend(packet);
    }
    else
        m_alife.graph().attach(*entry.npc, smart_cast<CSE_ALifeInventoryItem*>(entry.supply), entry.supply->m_tGraphID, true);
}

bool CNpcSimulation::update_online(CAI_Stalker& client, bool interrupted)
{
    if (m_entries.empty()) return false;
    auto entry = find(smart_cast<CSE_ALifeMonsterAbstract*>(objects().object(client.ID(), true)));
    if (!entry) return false;
    const auto decision = observe(*entry, client.Position(), client.ai_location().game_vertex_id(), interrupted, client.g_Alive(), false);
    if (interrupted || !client.g_Alive()) return true; // existing immediate planner owns movement now
    if (decision.action == 1)
    {
        client.movement().set_movement_type(MonsterSpace::eMovementTypeWalk);
        if (ai().game_graph().vertex(client.ai_location().game_vertex_id())->level_id() != decision.level)
        {
            client.movement().set_desired_position(nullptr);
            client.movement().set_path_type(MovementManager::ePathTypeGamePath);
            client.movement().set_game_dest_vertex(GameGraph::_GRAPH_ID(decision.game_vertex));
        }
        else if (ai().level_graph().valid_vertex_id(decision.level_vertex))
        {
            client.movement().set_path_type(MovementManager::ePathTypeLevelPath);
            client.movement().set_nearest_accessible_position(
                Fvector().set(decision.position[0], decision.position[1], decision.position[2]), decision.level_vertex);
        }
        else
        {
            observe(*entry, client.Position(), client.ai_location().game_vertex_id(), false, true, true);
            client.movement().set_movement_type(MonsterSpace::eMovementTypeStand);
        }
    }
    else
    {
        client.movement().set_movement_type(MonsterSpace::eMovementTypeStand);
        if (decision.action == 2) collect(*entry, &client, decision.command);
    }
    return true;
}

bool CNpcSimulation::update_offline(CSE_ALifeMonsterAbstract* object)
{
    auto entry = find(object);
    if (!entry) return false;
    if (object->m_bOnline) return true;
    const auto decision = observe(*entry, object->o_Position, object->m_tGraphID, false, object->fHealth > 0, false);
    auto& movement = object->brain().movement();
    if (decision.action == 1)
    {
        movement.path_type(MovementManager::ePathTypeGamePath);
        movement.detail().target(GameGraph::_GRAPH_ID(decision.game_vertex), decision.level_vertex,
            Fvector().set(decision.position[0], decision.position[1], decision.position[2]));
        movement.update();
    }
    else
    {
        movement.path_type(MovementManager::ePathTypeNoPath);
        if (decision.action == 2) collect(*entry, nullptr, decision.command);
    }
    return true;
}

void CNpcSimulation::remove(CSE_ALifeDynamicObject* object)
{
    for (auto it = m_entries.begin(); it != m_entries.end();)
    {
        if (it->second.npc == object)
        {
            npc_plan_destroy(it->second.plan);
            it = m_entries.erase(it);
        }
        else
        {
            if (it->second.supply == object) it->second.supply = nullptr;
            ++it;
        }
    }
}

void CNpcSimulation::died(CSE_ALifeDynamicObject* object)
{
    if (auto entry = find(smart_cast<CSE_ALifeMonsterAbstract*>(object)))
        observe(*entry, object->o_Position, object->m_tGraphID, false, false, false);
}

int CNpcSimulation::phase(u16 id) const
{
    if (!owns(id)) return -1;
    auto npc = smart_cast<CSE_ALifeHumanAbstract*>(objects().object(id));
    NpcDecision status{};
    R_ASSERT(npc_plan_status(m_entries.at(npc).plan, &status));
    return status.phase;
}

void CNpcSimulation::save(IWriter& stream) const
{
    stream.open_chunk(planner_chunk);
    stream.w_u32(1);
    stream.w_u64(m_next_identity);
    stream.w_u32(u32(m_entries.size()));
    xr_map<u64, const Entry*> ordered;
    for (const auto& [_, entry] : m_entries)
    {
        NpcDecision status{};
        R_ASSERT(npc_plan_status(entry.plan, &status));
        ordered.emplace(status.identity, &entry);
    }
    for (const auto& [_, value] : ordered)
    {
        const Entry& entry = *value;
        stream.w_u16(entry.npc->ID);
        stream.w_u16(entry.supply ? entry.supply->ID : u16(-1));
        const auto size = npc_plan_save(entry.plan, nullptr, 0);
        xr_vector<u8> bytes(size);
        R_ASSERT(npc_plan_save(entry.plan, bytes.data(), bytes.size()) == size);
        stream.w_u32(u32(size));
        stream.w(bytes.data(), u32(size));
    }
    stream.close_chunk();
}

void CNpcSimulation::load(IReader& source)
{
    R_ASSERT(m_entries.empty());
    IReader* chunk = source.open_chunk(planner_chunk);
    if (!chunk) return; // Existing saves enroll nobody.
    R_ASSERT2(chunk->length() >= 16 && chunk->r_u32() == 1, "Unsupported NPC planner save");
    m_next_identity = chunk->r_u64();
    const u32 count = chunk->r_u32();
    R_ASSERT(count <= objects().objects().size() && m_next_identity != 0);
    xr_set<u64> identities;
    for (u32 index = 0; index < count; ++index)
    {
        R_ASSERT(chunk->elapsed() >= 8);
        auto npc = smart_cast<CSE_ALifeHumanAbstract*>(objects().object(chunk->r_u16(), true));
        const u16 item_id = chunk->r_u16();
        auto supply = item_id == u16(-1) ? nullptr : objects().object(item_id, true);
        const u32 size = chunk->r_u32();
        R_ASSERT(npc && m_entries.find(npc) == m_entries.end() && size <= chunk->elapsed() && size <= 4096);
        R_ASSERT(item_id == u16(-1) || (supply && smart_cast<CSE_ALifeInventoryItem*>(supply)));
        xr_vector<u8> bytes(size);
        chunk->r(bytes.data(), size);
        NpcPlan* plan = npc_plan_load(bytes.data(), bytes.size());
        R_ASSERT2(plan, "Invalid NPC planner state");
        NpcLocation home{}, destination{};
        R_ASSERT(npc_plan_locations(plan, &home, &destination));
        R_ASSERT2(ai().game_graph().valid_vertex_id(GameGraph::_GRAPH_ID(home.game_vertex)) &&
            ai().game_graph().valid_vertex_id(GameGraph::_GRAPH_ID(destination.game_vertex)), "Saved NPC planner has an invalid game vertex");
        NpcDecision status{};
        R_ASSERT(npc_plan_status(plan, &status));
        R_ASSERT(status.identity < m_next_identity && identities.insert(status.identity).second);
        if (!configured(npc->name()))
        {
            Msg("[npc trip] discarded identity=%llu npc=%u: planner opt-in removed", status.identity, npc->ID);
            npc_plan_destroy(plan);
            continue;
        }
        m_entries.emplace(npc, Entry{npc, supply, plan});
        Msg("[npc trip] restore identity=%llu npc=%u phase=%u", status.identity, npc->ID, status.phase);
    }
    R_ASSERT(chunk->elapsed() == 0);
    chunk->close();
}
