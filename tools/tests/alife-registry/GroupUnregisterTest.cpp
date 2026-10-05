#include <iostream>
#include <map>
#include <stdexcept>
#include <string>
#include <vector>

void check(bool value, const char* message)
{
    if (!value) throw std::runtime_error(message);
}
#define VERIFY(value) check(value, #value)
constexpr bool FALSE = false;
constexpr unsigned flUsedAI_Locations = 1;
namespace ALife { using _OBJECT_ID = unsigned; }
struct Member { unsigned ID, m_group_id; };
struct Flags
{
    bool used = true;
    void set(unsigned flag, bool value) { check(flag == flUsedAI_Locations, "Wrong flag"); used = value; }
};
struct CSE_ALifeOnlineOfflineGroup;
struct Simulation
{
    bool unloading;
    CSE_ALifeOnlineOfflineGroup* owner = nullptr;
    std::vector<std::string> events;
    bool is_unloading() const { return unloading; }
    Simulation& graph() { check(!unloading, "Graph accessed during unload"); return *this; }
    Simulation& level() { check(!unloading, "Level accessed during unload"); return *this; }
    Simulation& scheduled() { check(!unloading, "Scheduler accessed during unload"); return *this; }
    void update(Member* member);
    void add(Member* member);
    void remove(CSE_ALifeOnlineOfflineGroup* group, unsigned vertex);
    void remove(CSE_ALifeOnlineOfflineGroup* group);
};
struct CSE_ALifeOnlineOfflineGroup
{
    using MEMBERS = std::map<unsigned, Member*>;
    MEMBERS m_members;
    unsigned ID = 7, ID_Parent = 0xffff, m_tGraphID = 22;
    bool m_bOnline = false;
    Flags m_flags;
    Simulation& simulation;
    explicit CSE_ALifeOnlineOfflineGroup(Simulation& value) : simulation(value) { value.owner = this; }
    Simulation& alife() { return simulation; }
    void unregister_member(ALife::_OBJECT_ID member_id);
};
void Simulation::update(Member* member)
{
    check(member->m_group_id == 0xffff, "Member still has group ID during graph update");
    check(owner->m_members.at(member->ID) == member, "Membership erased before graph update");
    events.push_back("graph " + std::to_string(member->ID));
}
void Simulation::add(Member* member)
{
    check(member->m_group_id == 0xffff && owner->m_members.at(member->ID) == member,
          "Incorrect membership at scheduler add");
    events.push_back("schedule " + std::to_string(member->ID));
}
void Simulation::remove(CSE_ALifeOnlineOfflineGroup* group, unsigned vertex)
{
    check(group == owner && group->m_members.empty() && vertex == 22 && group->m_flags.used,
          "Incorrect empty-group graph removal");
    events.push_back("remove graph");
}
void Simulation::remove(CSE_ALifeOnlineOfflineGroup* group)
{
    check(group == owner && group->m_members.empty() && group->m_flags.used,
          "Incorrect empty-group level removal");
    events.push_back("remove level");
}
#include "group-unregister.inc"

int main()
{
    try
    {
        for (bool unloading : {false, true})
            for (bool online : {false, true})
                for (bool attached : {false, true})
                {
                    Simulation simulation{unloading};
                    CSE_ALifeOnlineOfflineGroup group(simulation);
                    group.m_bOnline = online;
                    group.ID_Parent = attached ? 42 : 0xffff;
                    Member first{9, group.ID}, last{10, group.ID};
                    group.m_members = {{first.ID, &first}, {last.ID, &last}};
                    group.unregister_member(first.ID);
                    check(first.m_group_id == 0xffff && last.m_group_id == group.ID &&
                          group.m_members.size() == 1 && group.m_members.count(last.ID) && group.m_flags.used,
                          "Removing first member corrupted remaining membership");
                    group.unregister_member(last.ID);
                    check(last.m_group_id == 0xffff && group.m_members.empty() && !group.m_flags.used,
                          "Final member was not fully detached");
                    std::vector<std::string> expected;
                    if (!unloading)
                    {
                        expected = {"graph 9", "schedule 9", "graph 10", "schedule 10"};
                        if (!online) expected.push_back("remove graph");
                        else if (!attached) expected.push_back("remove level");
                    }
                    check(simulation.events == expected, "Unexpected registry operations or ordering");
                }
    }
    catch (const std::exception& error)
    {
        std::cerr << error.what() << '\n';
        return 1;
    }
    std::cout << "Unload detaches membership without registry access; live removal retains its registry effects\n";
}
