#include <iostream>
#include <limits>
#include <stdexcept>
struct State
{
    bool schedulable, needUpdate, scheduled, canOnline, canOffline, distanceMode, keepData, flipDuringMaintenance;
    bool online = false;
    float distance;
};
State* active;
void Msg(const char*, int, const char*) {}
struct Data
{
    bool present;
    bool empty() const { return !present; }
    void clear() { present = false; }
};
struct Position
{
    float distance_to(const Position&) { return active->distance; }
};
struct Actor { Position o_Position; };
struct Graph { Actor actorValue; Actor* actor() { return &actorValue; } };
struct Schedule
{
    bool object(int, bool) { return active->scheduled; }
    template<class T> void add(T*) { active->scheduled = true; }
    template<class T> void remove(T*) { active->scheduled = false; }
};
struct Simulator
{
    Schedule schedule; Graph graphValue;
    Schedule& scheduled() { return schedule; }
    Graph& graph() { return graphValue; }
    bool uses_distance_switching() { return active->distanceMode; }
    float online_distance() { return 150.f; }
    float offline_distance() { return 200.f; }
    template<class T> void switch_online(T*)
    {
        active->online = true;
    }
    template<class T> void switch_offline(T*) { active->online = false; }
};
struct CSE_ALifeSchedulable
{
    template<class T> bool need_update(T*)
    {

        if (active->flipDuringMaintenance) active->canOnline = !active->canOnline;
        return active->needUpdate;
    }
};
CSE_ALifeSchedulable schedulable;
template<class T, class U> T smart_cast(U*)
{
    return active->schedulable ? &schedulable : nullptr;
}
struct Operations
{
    int ID = 1;
    Data client_data;
    Position o_Position;
    Simulator simulator;
    Simulator& alife() { return simulator; }
    bool can_switch_online() { return active->canOnline; }
    bool can_switch_offline() { return active->canOffline; }
    bool keep_saved_data_anyway() { return active->keepData; }
    const char* name_replace() { return "fixture"; }
};
struct Candidate : Operations
{
    void try_switch_online(); void try_switch_offline();
};
#include "methods.inc"
void check(bool ok) { if (!ok) throw std::runtime_error("dynamic policy state mismatch"); }
int main()
{
    unsigned comparisons = 0;
    for (unsigned mask = 0; mask < 512; ++mask)
        for (float distance : {0.f, 149.f, 150.f, 151.f, 199.f, 200.f, 201.f,
                std::numeric_limits<float>::infinity(), std::numeric_limits<float>::quiet_NaN()})
            for (bool online : {false, true})
            {
                State current{bool(mask&1), bool(mask&2), bool(mask&4), bool(mask&8), bool(mask&16),
                    bool(mask&32), bool(mask&64), bool(mask&128)};
                current.distance = distance; current.online = online;
                const bool allowed = current.canOnline ^ (!online && current.schedulable && current.flipDuringMaintenance);
                const bool expectedOnline = online
                    ? !(current.canOffline && (!allowed || (current.distanceMode && !(distance <= 200.f))))
                    : allowed && (!current.canOffline || !current.distanceMode || !(distance > 150.f));
                const bool expectedScheduled = !online && current.schedulable ? current.needUpdate : current.scheduled;
                const bool expectedData = bool(mask&256) && (online || expectedOnline || current.keepData);
                Candidate object;
                object.client_data.present = bool(mask&256);
                active = &current;
                if (online) object.try_switch_offline(); else object.try_switch_online();
                check(current.online == expectedOnline && current.scheduled == expectedScheduled && current.canOnline == allowed);
                check(object.client_data.present == expectedData);
                ++comparisons;
            }
    std::cout << comparisons << " policy state cases passed\n";
}
