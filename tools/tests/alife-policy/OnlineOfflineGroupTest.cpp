#include "alife_switch_policy.h"
#include <iostream>
#include <limits>
#include <stdexcept>
#include <vector>
struct Operations
{
    std::vector<float> positions;
    bool distance=true, online=false, allow_online=true, allow_offline=true;
    float selected=0;
    unsigned attempts=0;
    const std::vector<float>& members() const { return positions; }
    bool can_online() const { return allow_online; }
    bool can_offline() const { return allow_offline; }
    bool distance_mode() const { return distance; }
    void check_distance() const { if (!distance) throw std::runtime_error("Whole-map distance evaluation"); }
    float actor_distance(float position) const { check_distance(); return position; }
    float offline_limit() const { return 200; }
    void select_actor_position() { selected=0; }
    void select_member_position(float position) { selected=position; }
    void verify_online_member(float) const {}
    void verify_offline_member(float) const {}
    // Execute the same dynamic policy used by the inherited engine method.
    void dynamic_online() { ++attempts; alife_switch_policy::dynamic_online(*this); }
    bool schedulable() const { return false; }
    bool needs_update() const { throw std::runtime_error("Unexpected schedule access"); }
    bool scheduled() const { throw std::runtime_error("Unexpected schedule access"); }
    void schedule() { throw std::runtime_error("Unexpected schedule access"); }
    void unschedule() { throw std::runtime_error("Unexpected schedule access"); }
    float actor_distance() const { check_distance(); return selected; }
    float online_limit() const { return 150; }
    void report_rejection(bool) const {}
    bool keep_data() const { return false; }
    void clear_data() {}
    void switch_online() { online=true; }
    void switch_offline() { online=false; }
};
int main()
{
    unsigned cases=0;
    try
    {
        const float nan=std::numeric_limits<float>::quiet_NaN();
        for (bool distance : {false,true})
            for (bool online : {false,true})
                for (bool allow_online : {false,true})
                    for (bool allow_offline : {false,true})
                        for (std::vector<float> positions : {std::vector<float>{}, {100}, {300}, {200}, {300,100}, {175,100}, {nan}})
                        {
                            Operations op;
                            op.positions=positions; op.distance=distance; op.online=online;
                            op.allow_online=allow_online; op.allow_offline=allow_offline;
                            bool expected=online;
                            float selected=0;
                            unsigned attempts=0;
                            if (!positions.empty() && online && allow_offline)
                            {
                                bool near=false;
                                for (float x : positions) if (x <= 200) near=true;
                                expected=allow_online && (!distance || near);
                            }
                            else if (!positions.empty() && !online && allow_online)
                            {
                                if (!allow_offline) { expected=true; attempts=1; }
                                else for (float x : positions)
                                    if (!distance || !(x > 200)) { selected=x; expected=!distance || !(x > 150); attempts=1; break; }
                            }
                            if (online) alife_switch_policy::online_group_offline(op);
                            else alife_switch_policy::online_group_online(op);
                            const bool same_position=op.selected==selected || (op.selected!=op.selected && selected!=selected);
                            if (op.online!=expected || !same_position || op.attempts!=attempts)
                                throw std::runtime_error("Incorrect state, selected member or inherited dispatch count");
                            ++cases;
                        }
    }
    catch (const std::exception& error) { std::cerr << "Online/offline group case " << cases << ": " << error.what() << '\n'; return 1; }
    std::cout << cases << " production online/offline group cases passed\n";
}
