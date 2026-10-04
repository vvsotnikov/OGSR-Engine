#include <map>
#include <cmath>
#include <stdexcept>
#include <iostream>
void check(bool ok) { if (!ok) throw std::runtime_error("online/offline group policy mismatch"); }
#define VERIFY3(x, ...) check(x)
struct Position { float x = 0; float distance_to(const Position& p) const { return std::abs(x - p.x); } };
struct Member
{
    Position o_Position;
    bool g_Alive() const { return true; }
    bool can_switch_online() const { return true; }
    bool can_switch_offline() const { return true; }
};
struct Simulator
{
    bool distance = true;
    Member actorValue;
    Simulator& graph() { return *this; }
    Member* actor() { return &actorValue; }
    bool uses_distance_switching() const { return distance; }
    float offline_distance() const { return 200; }
    template<class T> void switch_offline(T* object) { object->online = false; }
};
struct Base
{
    Simulator simulator;
    Position o_Position;
    bool online = false, allowOnline = true, allowOffline = true;
    Simulator& alife() { return simulator; }
    bool can_switch_online() const { return allowOnline; }
    bool can_switch_offline() const { return allowOffline; }
    // The inherited dynamic-object gate uses the tighter online threshold.
    void try_switch_online()
    {
        if (allowOnline && (!allowOffline || !simulator.distance || o_Position.x <= 150)) online = true;
    }
};
struct Candidate : Base
{
    using inherited1 = Base;
    using MEMBERS = std::map<unsigned, Member*>;
    MEMBERS m_members;
    void try_switch_online();
    void try_switch_offline();
};
#include "online-offline-group-methods.inc"
int main()
{
    for (bool distance : {false, true})
        for (bool online : {false, true})
            for (bool allowOnline : {false, true})
                for (bool allowOffline : {false, true})
                    // A first member in the hysteresis band stops the online
                    // scan before a later near member; preserve that ordering.
                    for (auto positions : {std::initializer_list<float>{}, {100}, {300}, {200}, {300, 100}, {175, 100}})
                    {
                        Candidate group;
                        Member members[2];
                        unsigned i = 0;
                        for (float x : positions) { members[i].o_Position.x = x; group.m_members[i] = &members[i]; ++i; }
                        group.simulator.distance = distance; group.online = online;
                        group.allowOnline = allowOnline; group.allowOffline = allowOffline;
                        bool expected = online;
                        float selected = 0;
                        if (positions.size() && online && allowOffline)
                        {
                            bool near = false;
                            for (float x : positions) if (x <= 200) near = true;
                            expected = allowOnline && (!distance || near);
                        }
                        else if (positions.size() && !online && allowOnline)
                        {
                            if (!allowOffline) expected = true;
                            else for (float x : positions)
                                if (!distance || x <= 200) { selected = x; expected = !distance || x <= 150; break; }
                        }
                        if (online) group.try_switch_offline(); else group.try_switch_online();
                        check(group.online == expected);
                        if (!online) check(group.o_Position.x == selected);
                    }
    std::cout << "Online/offline group permissions, distances and member ordering passed\n";
}
