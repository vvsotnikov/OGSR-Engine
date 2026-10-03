#include <iostream>
#include <limits>
#include <stdexcept>
#include <string>
#include <vector>
struct State
{
    bool schedulable, needUpdate, scheduled, canOnline, canOffline, distanceMode, keepData, queued, flipDuringMaintenance;
    bool online = false;
    float distance;
    std::vector<std::string> log;
};
State* active;
void record(const char* text) { active->log.push_back(text); }
void Msg(const char* text, int, const char*) { record(text); }
struct Data
{
    bool present;
    bool empty() const { record("data.empty"); return !present; }
    void clear() { record("data.clear"); present = false; }
};
struct Position
{
    float distance_to(const Position&) { record("distance"); return active->distance; }
};
struct Actor { Position o_Position; };
struct Graph { Actor actorValue; Actor* actor() { return &actorValue; } };
struct Schedule
{
    bool object(int, bool) { record("scheduled.object"); return active->scheduled; }
    template<class T> void add(T*) { record("scheduled.add"); active->scheduled = true; }
    template<class T> void remove(T*) { record("scheduled.remove"); active->scheduled = false; }
};
struct Simulator
{
    Schedule schedule; Graph graphValue;
    Schedule& scheduled() { return schedule; }
    Graph& graph() { return graphValue; }
    bool uses_distance_switching() { record("distance.mode"); return active->distanceMode; }
    float online_distance() { record("online.distance"); return 150.f; }
    float offline_distance() { record("offline.distance"); return 200.f; }
    template<class T> void switch_online(T*)
    {
        record(active->queued ? "queue.online" : "switch.online");
        if (!active->queued) active->online = true;
    }
    template<class T> void switch_offline(T*) { record("switch.offline"); active->online = false; }
};
struct CSE_ALifeSchedulable
{
    template<class T> bool need_update(T*)
    {
        record("need_update");
        if (active->flipDuringMaintenance) active->canOnline = !active->canOnline;
        return active->needUpdate;
    }
};
CSE_ALifeSchedulable schedulable;
template<class T, class U> T smart_cast(U*)
{
    record("cast"); return active->schedulable ? &schedulable : nullptr;
}
struct Operations
{
    int ID = 1;
    Data client_data;
    Position o_Position;
    Simulator simulator;
    Simulator& alife() { return simulator; }
    bool can_switch_online() { record("can.online"); return active->canOnline; }
    bool can_switch_offline() { record("can.offline"); return active->canOffline; }
    bool keep_saved_data_anyway() { record("keep.data"); return active->keepData; }
    const char* name_replace() { return "fixture"; }
};
struct Baseline : Operations { void try_switch_online(); void try_switch_offline(); };
struct Candidate : Operations
{
    enum class OnlineSwitchDecision { denied, outside_distance, activate };
    void maintain_offline_schedule();
    OnlineSwitchDecision evaluate_online_switch();
    bool evaluate_offline_switch();
    void try_switch_online(); void try_switch_offline();
};
#include "methods.inc"
void check(bool ok) { if (!ok) throw std::runtime_error("dynamic policy ordering/state mismatch"); }
int main()
{
    unsigned comparisons = 0;
    for (unsigned mask = 0; mask < 1024; ++mask)
        for (float distance : {0.f, 149.f, 150.f, 151.f, 199.f, 200.f, 201.f,
                std::numeric_limits<float>::infinity(), std::numeric_limits<float>::quiet_NaN()})
            for (bool online : {false, true})
            {
                State old{bool(mask&1), bool(mask&2), bool(mask&4), bool(mask&8), bool(mask&16),
                    bool(mask&32), bool(mask&64), bool(mask&128), bool(mask&256)};
                old.distance = distance; old.online = online;
                auto current = old;
                Baseline a; Candidate b;
                a.client_data.present = b.client_data.present = bool(mask&512);
                active = &old;
                if (online) a.try_switch_offline(); else a.try_switch_online();
                active = &current;
                if (online) b.try_switch_offline(); else b.try_switch_online();
                check(old.log == current.log);
                check(old.online == current.online && old.scheduled == current.scheduled && old.canOnline == current.canOnline);
                check(a.client_data.present == b.client_data.present);
                ++comparisons;
            }
    std::cout << comparisons << " real-method comparisons passed\n";
}
