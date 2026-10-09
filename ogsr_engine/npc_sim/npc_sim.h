#pragma once
#include <cstddef>
#include <cstdint>

struct NpcPlan;
struct NpcLocation
{
    std::uint32_t game_vertex, level_vertex;
    float position[3];
};
struct NpcObservation
{
    std::uint32_t at_source, at_home;
    std::uint32_t supply; // unknown=0, available=1, owned=2, unavailable=3
    std::uint32_t interrupted, alive, execution_failed;
};
struct NpcDecision
{
    std::uint64_t identity, command;
    std::uint32_t phase; // outbound=0, collecting=1, returning=2, complete=3, failed=4, dead=5
    std::uint32_t interrupted, action; // wait=0, travel=1, collect=2
    std::uint32_t game_vertex, level_vertex;
    float position[3];
};
static_assert(sizeof(NpcLocation) == 20 && sizeof(NpcObservation) == 24 && sizeof(NpcDecision) == 48);

// Unique ownership, serialized calls, valid non-overlapping buffers. The caller
// retains buffer ownership; only npc_plan_destroy may free a plan.
extern "C"
{
NpcPlan* npc_plan_create(std::uint64_t identity, const NpcLocation* home, const NpcLocation* source);
void npc_plan_destroy(NpcPlan*);
bool npc_plan_step(NpcPlan*, const NpcObservation*, NpcDecision*);
bool npc_plan_status(const NpcPlan*, NpcDecision*);
bool npc_plan_locations(const NpcPlan*, NpcLocation* home, NpcLocation* source);
std::size_t npc_plan_save(const NpcPlan*, std::uint8_t* output, std::size_t capacity);
NpcPlan* npc_plan_load(const std::uint8_t* input, std::size_t length);
}
