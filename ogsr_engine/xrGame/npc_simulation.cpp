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
#include "level_path_manager.h"
#include "game_location_selector.h"
#include "ai_space.h"
#include "level.h"
#include "game_graph.h"
#include "level_graph.h"
#include "game_level_cross_table.h"
#include "xrMessages.h"
#include "clsid_game.h"
#include "script_engine.h"
#include "script_binder_object.h"

extern u16 script_server_object_version();

namespace
{
constexpr u32 planner_chunk = 0x4e504331; // NPC1; optional root chunk, independent of legacy registry order.
NpcScriptControl script_control(u16 id)
{
    luabind::functor<u32> query;
    R_ASSERT2(ai().script_engine().functor("npc_sim_bridge.script_control", query), "NPC planner requires npc_sim_bridge.script");
    const u32 value = query(id);
    R_ASSERT(value <= u32(NpcScriptControl::Owned));
    return NpcScriptControl(value);
}
NpcLocation location(const CSE_ALifeDynamicObject& object)
{
    const u32 level = ai().game_graph().valid_vertex_id(object.m_tGraphID) ? ai().game_graph().vertex(object.m_tGraphID)->level_id() : u32(-1);
    NpcLocation result{object.m_tGraphID, object.m_tNodeID, level, {object.o_Position.x, object.o_Position.y, object.o_Position.z}};
    if (object.m_bOnline)
    {
        if (auto client = smart_cast<CGameObject*>(Level().Objects.net_Find(object.ID)))
        {
            const auto& point = client->Position();
            result.level = ai().level_graph().level_id();
            result.position[0] = point.x; result.position[1] = point.y; result.position[2] = point.z;
        }
        else result.level = u32(-1);
    }
    return result;
}
NpcLocation navigation_location(const CSE_ALifeDynamicObject& object)
{
    auto result = location(object);
    Fvector point = Fvector().set(result.position[0], result.position[1], result.position[2]);
    result.level_vertex = ai().level_graph().vertex_id(object.m_tNodeID, point);
    result.game_vertex = ai().cross_table().vertex(result.level_vertex).game_vertex_id();
    if (!ai().level_graph().inside(result.level_vertex, point)) point = ai().level_graph().vertex_position(result.level_vertex);
    point.y = ai().level_graph().vertex_plane_y(result.level_vertex, point.x, point.z);
    result.position[0] = point.x; result.position[1] = point.y; result.position[2] = point.z;
    return result;
}
}

CNpcSimulation::~CNpcSimulation()
{
    for (auto& [_, entry] : m_entries) npc_agent_destroy(entry.plan);
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

namespace
{
bool navigable_here(const CSE_ALifeDynamicObject& object)
{
    if (!ai().get_level_graph() || !ai().game_graph().valid_vertex_id(object.m_tGraphID) ||
        ai().game_graph().vertex(object.m_tGraphID)->level_id() != ai().level_graph().level_id() ||
        !ai().level_graph().valid_vertex_id(object.m_tNodeID)) return false;
    const auto point = location(object);
    const Fvector position = Fvector().set(point.position[0], point.position[1], point.position[2]);
    return point.level == ai().level_graph().level_id() && _valid(position) && ai().level_graph().valid_vertex_position(position);
}
}

bool CNpcSimulation::enroll(u16 npc_id, u16 supply_id, bool medical_goal)
{
    auto npc = smart_cast<CSE_ALifeHumanAbstract*>(objects().object(npc_id, true));
    auto supply = supply_id == u16(-1) ? nullptr : objects().object(supply_id, true);
    if (!npc || npc->fHealth <= 0 || npc->m_story_id != ALife::_STORY_ID(-1) || npc->m_group_id != 0xffff ||
        npc->m_smart_terrain_id != 0xffff || owns(npc) || m_next_identity == u64(-1) || !configured(npc->name())) return false;
    if (npc->m_bOnline)
    {
        auto client = smart_cast<CAI_Stalker*>(Level().Objects.net_Find(npc_id));
        if (!client || client->GetScriptControl()) return false;
    }
    if (!navigable_here(*npc)) return false;
    if (!medical_goal && (!supply || !smart_cast<CSE_ALifeInventoryItem*>(supply) ||
        supply->ID_Parent != u16(-1) || !navigable_here(*supply))) return false;
    const auto home = navigation_location(*npc);
    NpcAgent* plan = nullptr;
    if (medical_goal) plan = npc_agent_create_goal(m_next_identity, &home);
    else
    {
        const auto source = navigation_location(*supply), physical = location(*supply);
        plan = npc_agent_create(m_next_identity, &home, &source, &physical);
    }
    if (!plan) return false;
    Msg("[npc trip] enroll identity=%llu npc=%u supply=%u goal=%u", m_next_identity, npc_id, supply_id, u32(medical_goal));
    ++m_next_identity;
    Entry entry{};
    entry.npc = npc;
    entry.plan = plan;
    if (!medical_goal) entry.supplies.push_back(supply);
    m_entries.emplace(npc, std::move(entry));
    return true;
}

bool CNpcSimulation::remember(u16 npc_id, u16 supply_id)
{
    auto entry = find(smart_cast<CSE_ALifeMonsterAbstract*>(objects().object(npc_id, true)));
    auto supply = objects().object(supply_id, true);
    if (!entry || !supply || supply->m_tClassID != CLSID_IITEM_BANDAGE ||
        supply->ID_Parent != u16(-1) || !navigable_here(*supply)) return false;
    const auto found = std::find(entry->supplies.begin(), entry->supplies.end(), supply);
    const auto index = found == entry->supplies.end() ? npc_agent_available_source_slot(entry->plan) : u32(found - entry->supplies.begin());
    if (index == u32(-1)) return false;
    const auto navigation = navigation_location(*supply), physical = location(*supply);
    if (!npc_agent_remember(entry->plan, index, &navigation, &physical)) return false;
    if (index == entry->supplies.size()) entry->supplies.push_back(supply);
    else entry->supplies[index] = supply;
    return true;
}

NpcDecision CNpcSimulation::observe(Entry& entry, const Fvector& here, u32 graph, bool interrupted, bool alive, bool blocked, NpcScriptControl control)
{
    NpcDecision before{}, after{};
    R_ASSERT(npc_agent_status(entry.plan, &before));
    NpcObservation input{};
    const u32 level = ai().game_graph().valid_vertex_id(GameGraph::_GRAPH_ID(graph)) ? ai().game_graph().vertex(GameGraph::_GRAPH_ID(graph))->level_id() : u32(-1);
    input.current = {graph, entry.npc->m_tNodeID, level, {here.x, here.y, here.z}};
    if (!entry.npc->m_bOnline)
    {
        const auto& detail = entry.npc->brain().movement().detail();
        input.edge_distance = detail.path().size() > 1 ? detail.walked_distance() : 0.f;
    }
    input.interrupted = interrupted;
    input.alive = alive;
    input.path_blocked = blocked;
    input.pickup_pending = entry.pickup_command == before.command;
    input.elapsed_ms = entry.observed && entry.was_online == entry.npc->m_bOnline ? Device.dwTimeGlobal - entry.last_observation : 0;
    entry.was_online = entry.npc->m_bOnline;
    entry.observed = true;
    entry.last_observation = Device.dwTimeGlobal;
    // Server ownership is authoritative in both representations; client spawn
    // and inventory replication can temporarily lag it.
    for (const auto id : entry.npc->children)
        if (auto item = objects().object(id, true); item && item->ID_Parent == entry.npc->ID && item->m_tClassID == CLSID_IITEM_BANDAGE)
            ++input.bandages;
    if (before.source < entry.supplies.size())
        if (auto supply = entry.supplies[before.source])
        {
            input.supply = supply->ID_Parent == entry.npc->ID ? 2 : supply->ID_Parent == u16(-1) ? 1 : 3;
            input.supply_location = location(*supply);
            input.representation_ready = supply->m_bOnline == entry.npc->m_bOnline;
        }
    // World facts are distinct from knowledge: Rust decides what can be learned
    // at the remembered destination and owns arrival, waiting and failure policy.
    R_ASSERT(npc_agent_step(entry.plan, &input, &after, control));
    if (before.phase != after.phase || before.command != after.command || entry.interrupted != bool(after.interrupted))
        Msg("[npc trip] identity=%llu npc=%u command=%llu phase=%u reason=%u interrupted=%u online=%u source=%u bandages=%u", after.identity,
            entry.npc->ID, after.command, after.phase, after.reason, after.interrupted, u32(entry.npc->m_bOnline), after.source, input.bandages);
    entry.interrupted = bool(after.interrupted);
    return after;
}

void CNpcSimulation::collect(Entry& entry, CAI_Stalker* client, const NpcDecision& decision)
{
    if (decision.source >= entry.supplies.size()) return;
    auto supply = entry.supplies[decision.source];
    if (entry.pickup_command == decision.command || !supply || supply->ID_Parent != 0xffff ||
        entry.npc->m_bOnline != supply->m_bOnline) return;
    entry.pickup_command = decision.command;
    if (client)
    {
        NET_Packet packet;
        CGameObject::u_EventGen(packet, GE_OWNERSHIP_TAKE, entry.npc->ID);
        packet.w_u16(supply->ID);
        CGameObject::u_EventSend(packet);
    }
    else
        m_alife.graph().attach(*entry.npc, smart_cast<CSE_ALifeInventoryItem*>(supply), supply->m_tGraphID, true);
}

bool CNpcSimulation::update_online(CAI_Stalker& client, bool interrupted)
{
    if (m_entries.empty()) return false;
    auto entry = find(smart_cast<CSE_ALifeMonsterAbstract*>(objects().object(client.ID(), true)));
    if (!entry) return false;
    NpcDecision status{};
    R_ASSERT(npc_agent_status(entry->plan, &status));
    const bool path_failed = !entry->interrupted && entry->online_path_command == status.command &&
        client.movement().path_type() == MovementManager::ePathTypeLevelPath && client.movement().level_path().failed();
    if (interrupted) entry->online_path_command = 0;
    const auto decision = observe(*entry, client.Position(), client.ai_location().game_vertex_id(), interrupted, client.g_Alive(), path_failed, script_control(client.ID()));
    if (interrupted || !client.g_Alive()) return true; // existing immediate planner owns movement now
    if (decision.action == 1)
    {
        client.movement().set_movement_type(MonsterSpace::eMovementTypeWalk);
        if (ai().level_graph().level_id() == decision.level && ai().level_graph().valid_vertex_id(decision.level_vertex))
        {
            const Fvector destination = Fvector().set(decision.position[0], decision.position[1], decision.position[2]);
            // Keep an issued approach through detours across graph regions.
            // Interruption, representation changes and new commands rebuild it.
            if (entry->online_path_command != decision.command &&
                client.ai_location().game_vertex_id() != decision.game_vertex && client.Position().distance_to_sqr(destination) > 64.f)
            {
                // Native graph legs bound level-path searches on long routes.
                // Random branching would overwrite this explicit destination.
                // Owned NPCs never return to autonomous wandering in this lifetime.
                client.movement().game_selector().set_selection_type(eSelectionTypeMask);
                client.movement().set_desired_position(nullptr);
                client.movement().set_path_type(MovementManager::ePathTypeGamePath);
                client.movement().set_game_dest_vertex(GameGraph::_GRAPH_ID(decision.game_vertex));
                entry->online_path_command = 0;
            }
            else
            {
                // Close final approach also works across a game-vertex boundary.
                if (entry->online_path_command != decision.command) client.movement().level_path().reset();
                client.movement().set_path_type(MovementManager::ePathTypeLevelPath);
                client.movement().set_nearest_accessible_position(destination, decision.level_vertex);
                entry->online_path_command = decision.command;
            }
        }
        else
        {
            // A restored or externally teleported NPC may no longer be on the
            // plan's level. Do not pass that level's node into this level graph;
            // the stationary timeout bounds this unsupported execution.
            client.movement().set_movement_type(MonsterSpace::eMovementTypeStand);
        }
    }
    else
    {
        client.movement().set_movement_type(MonsterSpace::eMovementTypeStand);
        if (decision.action == 2) collect(*entry, &client, decision);
    }
    return true;
}

bool CNpcSimulation::update_offline(CSE_ALifeMonsterAbstract* object)
{
    auto entry = find(object);
    if (!entry) return false;
    if (object->m_bOnline) return true;
    entry->online_path_command = 0;
    const auto decision = observe(*entry, object->o_Position, object->m_tGraphID, false, object->fHealth > 0, false, NpcScriptControl::Unobserved);
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
        if (decision.action == 2) collect(*entry, nullptr, decision);
    }
    return true;
}

void CNpcSimulation::before_offline(CSE_ALifeDynamicObject* object)
{
    auto entry = find(smart_cast<CSE_ALifeMonsterAbstract*>(object));
    if (!entry) return;
    auto client = smart_cast<CAI_Stalker*>(Level().Objects.net_Find(object->ID));
    if (!client || client->getDestroy()) return;
    NET_Packet packet;
    client->CScriptBinder::save(packet);
}

void CNpcSimulation::capture_binder(u16 id, const u8* data, u32 size)
{
    auto entry = find(smart_cast<CSE_ALifeMonsterAbstract*>(objects().object(id, true)));
    if (!entry) return;
    // ClientSave also reaches this path before a level-change autosave, where
    // switch_offline is not called. Saving must not advance goal time or actions.
    R_ASSERT(npc_agent_script_control(entry->plan, script_control(id)));
    entry->binder_version = script_server_object_version();
    entry->binder_data.assign(data, data + size);
}

void CNpcSimulation::discard_binder(u16 id)
{
    if (auto entry = find(smart_cast<CSE_ALifeMonsterAbstract*>(objects().object(id, true))))
        entry->binder_data.clear();
}

void CNpcSimulation::restore_binder(u16 id, CScriptBinderObject& binder)
{
    auto entry = find(smart_cast<CSE_ALifeMonsterAbstract*>(objects().object(id, true)));
    if (!entry || entry->binder_data.empty()) return;
    IReader reader(entry->binder_data.data(), entry->binder_data.size());
    // Legacy binder loaders consult the server's input format version. A new
    // in-memory snapshot uses today's writer even when that entity is older.
    struct RestoreVersion
    {
        CSE_Abstract& object;
        u16 previous;
        ~RestoreVersion() { object.m_script_version = previous; }
    } restore{*entry->npc, entry->npc->m_script_version};
    entry->npc->m_script_version = entry->binder_version;
    binder.load(&reader);
    R_ASSERT2(reader.elapsed() == 0, "NPC binder did not consume its saved payload");
    entry->binder_data.clear();
}

void CNpcSimulation::remove(CSE_ALifeDynamicObject* object)
{
    for (auto it = m_entries.begin(); it != m_entries.end();)
    {
        if (it->second.npc == object)
        {
            npc_agent_destroy(it->second.plan);
            it = m_entries.erase(it);
        }
        else
        {
            for (auto& supply : it->second.supplies)
                if (supply == object) supply = nullptr;
            ++it;
        }
    }
}

void CNpcSimulation::died(CSE_ALifeDynamicObject* object)
{
    if (auto entry = find(smart_cast<CSE_ALifeMonsterAbstract*>(object)))
        observe(*entry, object->o_Position, object->m_tGraphID, false, false, false, NpcScriptControl::Unobserved);
}

int CNpcSimulation::phase(u16 id) const
{
    if (!owns(id)) return -1;
    auto npc = smart_cast<CSE_ALifeHumanAbstract*>(objects().object(id));
    NpcDecision status{};
    R_ASSERT(npc_agent_status(m_entries.at(npc).plan, &status));
    return status.phase;
}

void CNpcSimulation::save(IWriter& stream) const
{
    stream.open_chunk(planner_chunk);
    stream.w_u32(3);
    stream.w_u64(m_next_identity);
    stream.w_u32(u32(m_entries.size()));
    xr_map<u64, const Entry*> ordered;
    for (const auto& [_, entry] : m_entries)
    {
        NpcDecision status{};
        R_ASSERT(npc_agent_status(entry.plan, &status));
        ordered.emplace(status.identity, &entry);
    }
    for (const auto& [_, value] : ordered)
    {
        const Entry& entry = *value;
        stream.w_u16(entry.npc->ID);
        stream.w_u16(u16(entry.supplies.size()));
        for (auto supply : entry.supplies) stream.w_u16(supply ? supply->ID : u16(-1));
        const auto size = npc_agent_save(entry.plan, nullptr, 0);
        xr_vector<u8> bytes(size);
        R_ASSERT(npc_agent_save(entry.plan, bytes.data(), bytes.size()) == size);
        stream.w_u32(u32(size));
        stream.w(bytes.data(), u32(size));
        stream.w_u16(entry.binder_version);
        stream.w_u32(u32(entry.binder_data.size()));
        if (!entry.binder_data.empty()) stream.w(entry.binder_data.data(), u32(entry.binder_data.size()));
    }
    stream.close_chunk();
}

void CNpcSimulation::load(IReader& source)
{
    R_ASSERT(m_entries.empty());
    IReader* chunk = source.open_chunk(planner_chunk);
    if (!chunk) return; // Existing saves enroll nobody.
    R_ASSERT(chunk->length() >= 16);
    const u32 version = chunk->r_u32();
    R_ASSERT2(version == 1 || version == 2 || version == 3, "Unsupported NPC planner save");
    m_next_identity = chunk->r_u64();
    const u32 count = chunk->r_u32();
    R_ASSERT(count <= objects().objects().size() && m_next_identity != 0);
    xr_set<u64> identities;
    for (u32 index = 0; index < count; ++index)
    {
        R_ASSERT(chunk->elapsed() >= 8);
        auto npc = smart_cast<CSE_ALifeHumanAbstract*>(objects().object(chunk->r_u16(), true));
        const u16 source_count = version == 1 ? 1 : chunk->r_u16();
        R_ASSERT(source_count <= 256 && chunk->elapsed() >= source_count * 2u + 4u);
        xr_vector<CSE_ALifeDynamicObject*> supplies;
        for (u16 i = 0; i < source_count; ++i)
        {
            const u16 item_id = chunk->r_u16();
            auto supply = item_id == u16(-1) ? nullptr : objects().object(item_id, true);
            R_ASSERT(item_id == u16(-1) || (supply && smart_cast<CSE_ALifeInventoryItem*>(supply)));
            supplies.push_back(supply);
        }
        const u32 size = chunk->r_u32();
        R_ASSERT(npc && m_entries.find(npc) == m_entries.end() && size <= chunk->elapsed() && size <= 16384);
        xr_vector<u8> bytes(size);
        chunk->r(bytes.data(), size);
        xr_vector<u8> binder_data;
        u16 binder_version = 0;
        if (version >= 3)
        {
            R_ASSERT(chunk->elapsed() >= 6);
            binder_version = chunk->r_u16();
            const u32 binder_size = chunk->r_u32();
            R_ASSERT(binder_size <= chunk->elapsed() && binder_size <= NET_PacketSizeLimit);
            binder_data.resize(binder_size);
            if (binder_size) chunk->r(binder_data.data(), binder_size);
        }
        NpcAgent* plan = npc_agent_load(bytes.data(), bytes.size());
        R_ASSERT2(plan, "Invalid NPC planner state");
        R_ASSERT(npc_agent_source_count(plan) == supplies.size());
        for (u32 i = 0; i < supplies.size(); ++i)
        {
            NpcLocation remembered{};
            R_ASSERT(npc_agent_source(plan, i, &remembered));
            R_ASSERT(ai().game_graph().valid_vertex_id(GameGraph::_GRAPH_ID(remembered.game_vertex)));
        }
        NpcLocation home{}, destination{};
        R_ASSERT(npc_agent_locations(plan, &home, &destination));
        R_ASSERT2(ai().game_graph().valid_vertex_id(GameGraph::_GRAPH_ID(home.game_vertex)) &&
            ai().game_graph().valid_vertex_id(GameGraph::_GRAPH_ID(destination.game_vertex)), "Saved NPC planner has an invalid game vertex");
        NpcDecision status{};
        R_ASSERT(npc_agent_status(plan, &status));
        R_ASSERT(status.identity < m_next_identity && identities.insert(status.identity).second);
        if (!configured(npc->name()))
        {
            Msg("[npc trip] discarded identity=%llu npc=%u: planner opt-in removed", status.identity, npc->ID);
            npc_agent_destroy(plan);
            continue;
        }
        Entry entry{};
        entry.npc = npc;
        entry.supplies = std::move(supplies);
        entry.plan = plan;
        entry.binder_data = std::move(binder_data);
        entry.binder_version = binder_version;
        m_entries.emplace(npc, std::move(entry));
        Msg("[npc trip] restore identity=%llu npc=%u phase=%u", status.identity, npc->ID, status.phase);
    }
    R_ASSERT(chunk->elapsed() == 0);
    chunk->close();
}
