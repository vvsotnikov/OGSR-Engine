#pragma once
#include "../npc_sim/npc_sim.h"

class CSE_ALifeDynamicObject;
class CSE_ALifeMonsterAbstract;
class CSE_ALifeHumanAbstract;
class CAI_Stalker;
class CALifeSimulatorBase;
class CALifeObjectRegistry;

// Engine bindings are transient pointers owned by the ALife object registry.
// Rust owns intentions; engine IDs are used only to bind a consistent save.
class CNpcSimulation
{
    struct Entry
    {
        CSE_ALifeHumanAbstract* npc{};
        xr_vector<CSE_ALifeDynamicObject*> supplies;
        NpcAgent* plan{};
        u64 pickup_command = 0;
        u64 online_path_command = 0;
        u32 last_observation = 0;
        bool observed = false;
        bool was_online = false;
        bool interrupted = false;
    };
    CALifeSimulatorBase& m_alife;
    xr_map<CSE_ALifeHumanAbstract*, Entry> m_entries;
    u64 m_next_identity = 1;

    NpcDecision observe(Entry&, const Fvector&, u32 game_vertex, bool interrupted, bool alive, bool failed);
    void collect(Entry&, CAI_Stalker* client, const NpcDecision&);
    Entry* find(CSE_ALifeMonsterAbstract*);
    const CALifeObjectRegistry& objects() const;

public:
    explicit CNpcSimulation(CALifeSimulatorBase& alife) : m_alife(alife) {}
    ~CNpcSimulation();
    static CNpcSimulation* active();
    static bool configured(LPCSTR section);
    bool enroll(u16 npc, u16 supply, bool medical_goal = false);
    bool remember(u16 npc, u16 supply);
    bool owns(CSE_ALifeMonsterAbstract*) const;
    bool owns(u16 id) const;
    bool update_offline(CSE_ALifeMonsterAbstract*);
    bool update_online(CAI_Stalker&, bool interrupted = false);
    void remove(CSE_ALifeDynamicObject*);
    void died(CSE_ALifeDynamicObject*);
    int phase(u16 id) const;
    void save(IWriter&) const;
    void load(IReader&);
};
