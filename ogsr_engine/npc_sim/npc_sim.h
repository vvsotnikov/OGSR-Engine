#pragma once
#include <cstddef>
#include <cstdint>

struct NpcAgent;
enum class NpcControl : std::uint32_t { Ordinary = 0, Immediate = 1, Script = 2, Offline = 3 };
struct NpcLocation
{
    std::uint32_t game_vertex, level_vertex, level;
    float position[3];
};
struct NpcObservation
{
    NpcLocation current, supply_location;
    std::uint32_t supply; // missing=0, free=1, owned=2, other owner=3
    std::uint32_t representation_ready, pickup_pending, path_blocked, elapsed_ms;
    float edge_distance;
    std::uint32_t interrupted, alive;
    std::uint32_t bandages;
};
struct NpcDecision
{
    std::uint64_t identity, command;
    std::uint32_t phase; // outbound=0, collecting=1, returning=2, complete=3, failed=4, dead=5, waiting=6
    std::uint32_t interrupted, action; // wait=0, travel=1, collect=2
    std::uint32_t reason; // Rust FailureReason; zero unless failed
    std::uint32_t game_vertex, level_vertex, level;
    float position[3];
    std::uint32_t source; // source-memory index, UINT32_MAX if none
};
static_assert(sizeof(NpcLocation) == 24 && sizeof(NpcObservation) == 84 && sizeof(NpcDecision) == 64);

// Unique ownership, serialized calls, valid non-overlapping buffers. The caller
// retains buffer ownership; only npc_agent_destroy may free a plan.
extern "C"
{
NpcAgent* npc_agent_create(std::uint64_t identity, const NpcLocation* home, const NpcLocation* source, const NpcLocation* remembered_item);
NpcAgent* npc_agent_create_goal(std::uint64_t identity, const NpcLocation* home);
bool npc_agent_remember(NpcAgent*, std::uint32_t index, const NpcLocation* navigation, const NpcLocation* physical);
// UINT32_MAX if unavailable. Query and remember belong to one serialized operation.
std::uint32_t npc_agent_available_source_slot(const NpcAgent*);
std::size_t npc_agent_source_count(const NpcAgent*);
bool npc_agent_source(const NpcAgent*, std::uint32_t index, NpcLocation* navigation);
void npc_agent_destroy(NpcAgent*);
bool npc_agent_step(NpcAgent*, const NpcObservation*, NpcDecision*, NpcControl);
bool npc_agent_status(const NpcAgent*, NpcDecision*);
bool npc_agent_locations(const NpcAgent*, NpcLocation* home, NpcLocation* source);
std::size_t npc_agent_save(const NpcAgent*, std::uint8_t* output, std::size_t capacity);
NpcAgent* npc_agent_load(const std::uint8_t* input, std::size_t length);
}
