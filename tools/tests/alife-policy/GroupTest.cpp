#include "alife_switch_lifecycle.h"
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>
struct Member
{
    int id;
    bool alive = true, monster = true, allow_online = true, allow_offline = true, near = true;
};
struct Operations
{
    std::vector<Member> storage;
    std::vector<unsigned> order;
    std::vector<std::string> calls;
    bool distance = true, group_online_permission = false, group_offline_permission = true, switched = false;
    unsigned count = 0;
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
    void set_online(Member* member, bool online) { record(member, online ? "online" : "offline"); }
    void detach_if_attached(Member* member) { record(member, "detach"); }
    void register_member(Member* member) { record(member, "register"); }
    void remove_graph_if_unattached(Member* member) { record(member, "graph"); }
    void decrement_count() { --count; }
    void switch_offline() { switched = true; }
};
void run(const char* name, Operations op, std::vector<int> survivors, std::vector<int> corpses, bool switched)
{
    for (unsigned i=0; i<op.storage.size(); ++i) op.order.push_back(i);
    op.count = unsigned(op.order.size());
    alife_switch_lifecycle::legacy_group_offline(op);
    std::vector<int> actual;
    for (unsigned i : op.order) actual.push_back(op.storage[i].id);
    std::vector<std::string> expected;
    for (int id : corpses)
        for (const char* step : {"dead", "direct", "erase", "offline", "detach", "register", "graph", "online"})
            expected.push_back(std::to_string(id) + ":" + step);
    if (actual != survivors || op.count != survivors.size() || op.switched != switched || op.calls != expected)
        throw std::runtime_error(std::string(name) + ": membership, switch or corpse operation order differs");
}
int main()
{
    try
    {
        for (bool distance : {false, true})
            for (bool allowed : {false, true})
                for (bool near : {false, true})
                    for (bool dead_first : {false, true})
                    {
                        Member live{0}; live.near = near;
                        Member dead{1}; dead.alive = false;
                        Operations op;
                        op.storage = dead_first ? std::vector<Member>{dead,live} : std::vector<Member>{live,dead};
                        op.distance = distance; op.group_online_permission = allowed;
                        const bool blocks = !distance || near;
                        const bool cleaned = dead_first || !blocks;
                        run("corpse relative to blocking member", op, cleaned ? std::vector<int>{0} : std::vector<int>{0,1},
                            cleaned ? std::vector<int>{1} : std::vector<int>{}, allowed || !blocks);
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
