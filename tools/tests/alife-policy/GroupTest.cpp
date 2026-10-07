#include "alife_switch_policy.h"
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>
struct Member
{
    int id;
    bool alive = true, monster = true, allow_online = true, allow_offline = true, near = true, online_state = true;
};
struct Operations
{
    std::vector<Member> storage;
    std::vector<unsigned> order;
    std::vector<std::string> calls;
    bool distance = true, group_online_permission = false, group_offline_permission = true, switched = false;
    unsigned count = 0;
    bool container_online = true;
    unsigned size() const { return unsigned(order.size()); }
    void bind_group() {}
    Member* monster(unsigned i) { auto& member = storage.at(order.at(i)); return member.monster ? &member : nullptr; }
    bool alive(Member* member) const { return member->alive; }
    bool can_online(Member* member) const { return member->allow_online; }
    bool can_offline(Member* member) const { return member->allow_offline; }
    bool can_online() const { return group_online_permission; }
    bool can_offline() const { return group_offline_permission; }
    bool distance_mode() const { return distance; }
    float actor_distance(Member* member) const { if (!distance) throw std::runtime_error("Whole-map distance evaluation"); return member->near ? 149.f : 151.f; }
    float offline_limit() const { return 150; }
    void record(Member* member, const char* event) { calls.push_back(std::to_string(member->id) + ":" + event); }
    void mark_dead(Member* member) { record(member, "dead"); }
    void set_direct_control(Member* member) { record(member, "direct"); }
    void erase_member(unsigned i) { record(&storage[order[i]], "erase"); order.erase(order.begin() + i); }
    void set_online(Member* member, bool online) { record(member, online ? "online" : "offline"); member->online_state = online; }
    void detach_if_attached(Member* member) { record(member, "detach"); }
    void register_member(Member* member) { record(member, "register"); }
    void remove_graph_if_unattached(Member* member) { record(member, "graph"); }
    void decrement_count() { --count; }
    void switch_offline() { switched = true; }
    bool online(Member* member) const { return member->online_state; }
    bool online_at(unsigned i) const { return storage.at(order.at(i)).online_state; }
    void activate(Member* member, unsigned) { record(member, "activate"); member->online_state = true; }
    void deactivate(Member* member) { record(member, "deactivate"); member->online_state = false; }
    void group_online(bool value) { container_online = value; }
    void prepare_members() {}

};
void run(const char* name, Operations op, std::vector<int> survivors, std::vector<int> corpses, bool switched)
{
    for (unsigned i=0; i<op.storage.size(); ++i) op.order.push_back(i);
    op.count = unsigned(op.order.size());
    alife_switch_policy::legacy_group_offline(op);
    std::vector<int> actual;
    for (unsigned i : op.order) actual.push_back(op.storage[i].id);
    std::vector<std::string> expected;
    for (int id : corpses)
        for (const char* step : {"dead", "direct", "erase", "offline", "detach", "register", "graph", "online"})
            expected.push_back(std::to_string(id) + ":" + step);
    if (actual != survivors || op.count != survivors.size() || op.switched != switched || op.calls != expected)
        throw std::runtime_error(std::string(name) + ": membership, switch or corpse operation order differs");
}
void whole_map()
{
    const auto require = [](bool value, const char* message) { if (!value) throw std::runtime_error(message); };
    // All group/member permissions, including contradictory flags and initial
    // state. Repeated evaluations must not recreate a stable client.
    for (unsigned flags = 0; flags < 32; ++flags)
    {
        Operations op;
        op.distance = false;
        op.group_online_permission = (flags & 1) != 0;
        op.group_offline_permission = (flags & 2) != 0;
        Member live{0};
        live.allow_online = (flags & 4) != 0;
        live.allow_offline = (flags & 8) != 0;
        live.online_state = (flags & 16) != 0;
        const bool start = live.online_state;
        const bool allow_on = op.group_online_permission && live.allow_online;
        const bool allow_off = op.group_offline_permission && live.allow_offline;
        const bool expected = start ? (!allow_off || allow_on) : allow_on;
        op.storage = {live}; op.order = {0}; op.count = 1; op.container_online = start;
        for (unsigned pass = 0; pass < 4; ++pass)
        {
            alife_switch_policy::legacy_group_whole_map(op);
            require(op.storage[0].online_state == expected, "Whole-map member permission matrix");
            require(op.container_online == expected, "Container tracks member activity");
            require(op.order == std::vector<unsigned>{0} && op.count == 1, "Living membership retained");
        }
        require(op.calls.size() == (start == expected ? 0u : 1u), "Stable whole-map member must not churn");
    }
    for (bool dead_first : {false,true})
        for (bool was_online : {false,true})
        {
            Operations op;
            op.distance = false; op.group_online_permission = true;
            Member live{0}, dead{1}; dead.alive = false; dead.online_state = was_online;
            op.storage = {live,dead}; op.order = dead_first ? std::vector<unsigned>{1,0} : std::vector<unsigned>{0,1}; op.count = 2;
            alife_switch_policy::legacy_group_whole_map(op);
            require(op.order == std::vector<unsigned>{0} && op.count == 1, "All corpses detached independent of member order");
            require(op.storage[1].online_state == was_online, "Corpse keeps its original client state");
            std::vector<std::string> expected = {"1:dead","1:direct","1:erase","1:offline","1:detach","1:register"};
            if (was_online) expected.push_back("1:graph");
            expected.push_back(was_online ? "1:online" : "1:offline");
            require(op.calls == expected, "Corpse registration and graph ownership order");
            require(op.container_online, "Living group survives corpse cleanup");
        }
    Operations mixed;
    mixed.distance = false; mixed.group_online_permission = true;
    Member eligible{0}, excluded{1}, unknown{2};
    eligible.online_state = excluded.online_state = unknown.online_state = false;
    excluded.allow_online = false; unknown.monster = false;
    mixed.storage={eligible,excluded,unknown}; mixed.order={0,1,2}; mixed.count=3; mixed.container_online=false;
    alife_switch_policy::legacy_group_whole_map(mixed);
    require(mixed.storage[0].online_state && !mixed.storage[1].online_state && !mixed.storage[2].online_state, "Excluded/unknown member must not prevent eligible activation");
    mixed.storage[1].allow_online = true;
    alife_switch_policy::legacy_group_whole_map(mixed);
    require(mixed.storage[1].online_state, "Clearing an exclusion activates member in already-online group");
    mixed.storage[0].allow_online = false;
    alife_switch_policy::legacy_group_whole_map(mixed);
    require(!mixed.storage[0].online_state && mixed.storage[1].online_state && mixed.container_online, "New exclusion affects only that member");
    mixed.storage[1].alive = false;
    alife_switch_policy::legacy_group_whole_map(mixed);
    require(!mixed.container_online && mixed.count == 2, "No active members leaves container offline");
    Operations empty; empty.distance=false; empty.container_online=false;
    alife_switch_policy::legacy_group_whole_map(empty);
    require(!empty.container_online && empty.calls.empty(), "Empty group is inert");
    for (bool online : {false, true})
    {
        Operations dead_group;
        dead_group.distance = false; dead_group.container_online = online;
        Member dead{0}; dead.alive = false; dead.online_state = online;
        dead_group.storage = {dead}; dead_group.order = {0}; dead_group.count = 1;
        alife_switch_policy::legacy_group_whole_map(dead_group);
        require(dead_group.order.empty() && dead_group.count == 0 && !dead_group.container_online,
            "Last corpse leaves an empty offline owner for normal redundant-object removal");
        require(dead_group.storage[0].online_state == online, "Last corpse keeps its client state");
    }
}

int main()
{
    try
    {
        whole_map();
        for (bool allowed : {false, true})
            for (bool near : {false, true})
                for (bool dead_first : {false, true})
                {
                    Member live{0}; live.near = near;
                    Member dead{1}; dead.alive = false;
                    Operations op;
                    op.storage = dead_first ? std::vector<Member>{dead,live} : std::vector<Member>{live,dead};
                    op.group_online_permission = allowed;
                    const bool cleaned = dead_first || !near;
                    run("distance-mode corpse relative to blocking member", op, cleaned ? std::vector<int>{0} : std::vector<int>{0,1},
                        cleaned ? std::vector<int>{1} : std::vector<int>{}, allowed || !near);
                }
        run("empty group", {}, {}, {}, false);
        Member dead{1}; dead.alive=false;
        Member dead2{2}; dead2.alive=false;
        run("consecutive corpses", Operations{{dead,dead2}}, {}, {1,2}, false);
        Member live{0}; live.allow_offline=false;
        run("cannot-offline member is skipped", Operations{{live,dead}}, {0}, {1}, true);
        live.allow_offline=true; live.allow_online=false; live.near=false;
        run("cannot-online member stops cleanup", Operations{{live,dead}}, {0,1}, {}, false);
        Member unknown{3}; unknown.monster=false;
        run("non-monster skipped", Operations{{unknown,dead}}, {3}, {1}, true);
        Operations denied{{dead}}; denied.group_offline_permission=false;
        run("corpse cleanup before group permission", denied, {}, {1}, false);
        live.allow_online=true; live.near=false;
        denied.storage={live};
        run("group offline permission", denied, {0}, {}, false);
    }
    catch (const std::exception& error) { std::cerr << error.what() << '\n'; return 1; }
    std::cout << "Production legacy group traversal and corpse ordering passed\n";
}
