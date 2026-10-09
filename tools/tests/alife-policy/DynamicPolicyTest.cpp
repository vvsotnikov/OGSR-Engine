#include "alife_switch_lifecycle.h"
#include <iostream>
#include <limits>
#include <stdexcept>
#include <string>

struct Operations
{
    bool has_schedule = false, need_update = false, is_scheduled = false;
    bool allow_online = true, allow_offline = true, distance = true, keep = false, flip = false;
    bool online = false, data = true;
    float separation = 0;
    unsigned distance_reads = 0, rejections = 0;
    bool distance_rejection = false;
    bool schedulable() const { return has_schedule; }
    bool needs_update() { if (flip) allow_online = !allow_online; return need_update; }
    bool scheduled() const { return is_scheduled; }
    void schedule() { is_scheduled = true; }
    void unschedule() { is_scheduled = false; }
    bool can_online() const { return allow_online; }
    bool can_offline() const { return allow_offline; }
    bool distance_mode() const { return distance; }
    void read_distance() { if (!distance) throw std::runtime_error("Whole-map mode evaluated distance"); ++distance_reads; }
    float actor_distance() { read_distance(); return separation; }
    float online_limit() const { return 150; }
    float offline_limit() const { return 200; }
    bool keep_data() const { return keep; }
    void clear_data() { if (rejections != 1) throw std::runtime_error("Data cleared before reporting rejection"); data = false; }
    void report_rejection(bool distance) { ++rejections; distance_rejection = distance; }
    void switch_online() { online = true; }
    void switch_offline() { online = false; }
};
// Deliberately offers no registry, client-data or transition operations.
struct Queries
{
    Operations& op;
    bool can_online() const { return op.can_online(); }
    bool can_offline() const { return op.can_offline(); }
    bool distance_mode() const { return op.distance_mode(); }
    float actor_distance() const { return op.actor_distance(); }
    float online_limit() const { return op.online_limit(); }
    float offline_limit() const { return op.offline_limit(); }
};
void require(bool ok, const char* message) { if (!ok) throw std::runtime_error(message); }
int main()
{
    unsigned cases = 0;
    try
    {
        for (unsigned mask = 0; mask < 512; ++mask)
            for (float separation : {0.f, 149.f, 150.f, 151.f, 199.f, 200.f, 201.f,
                    std::numeric_limits<float>::infinity(), std::numeric_limits<float>::quiet_NaN()})
                for (bool online : {false, true})
                {
                    Operations op;
                    op.has_schedule = mask & 1; op.need_update = mask & 2; op.is_scheduled = mask & 4;
                    op.allow_online = mask & 8; op.allow_offline = mask & 16; op.distance = mask & 32;
                    op.keep = mask & 64; op.flip = mask & 128; op.data = mask & 256;
                    op.separation = separation; op.online = online;
                    const bool allowed = op.allow_online ^ (!online && op.has_schedule && op.flip);
                    const bool expected_online = online
                        ? !(op.allow_offline && (!allowed || (op.distance && !(separation <= 200))))
                        : allowed && (!op.allow_offline || !op.distance || !(separation > 150));
                    const bool expected_schedule = !online && op.has_schedule ? op.need_update : op.is_scheduled;
                    const bool expected_data = op.data && (online || expected_online || op.keep);
                    if (online) alife_switch_lifecycle::dynamic_offline(op);
                    else alife_switch_lifecycle::dynamic_online(op);
                    require(op.online == expected_online, "Incorrect online state");
                    require(op.is_scheduled == expected_schedule, "Incorrect scheduler membership");
                    require(op.allow_online == allowed, "Permission not refreshed after maintenance");
                    require(op.data == expected_data, "Incorrect saved client data retention");
                    const bool rejected = !online && !expected_online;
                    require(op.rejections == unsigned(rejected), "Incorrect rejection reporting");
                    require(op.distance_rejection == (rejected && allowed), "Incorrect rejection reason");
                    const unsigned reads = unsigned(allowed && op.allow_offline && op.distance);
                    require(op.distance_reads == reads, "Distance queried out of permission order");
                    Queries queries{op};
                    const auto decision = online ? alife_switch_policy::dynamic_offline(queries)
                                                 : alife_switch_policy::dynamic_online(queries);
                    using alife_switch_policy::Action;
                    using alife_switch_policy::Rejection;
                    const auto action = online ? (expected_online ? Action::keep : Action::deactivate)
                                               : (expected_online ? Action::activate : Action::keep);
                    const auto reason = online
                        ? (!op.allow_offline ? Rejection::permission
                           : action != Action::keep || !op.distance ? Rejection::none : Rejection::distance)
                        : (expected_online ? Rejection::none : allowed ? Rejection::distance : Rejection::permission);
                    require(decision.action == action && decision.rejection == reason, "Incorrect query-only decision");
                    ++cases;
                }
    }
    catch (const std::exception& error) { std::cerr << "Dynamic policy case " << cases << ": " << error.what() << '\n'; return 1; }
    std::cout << cases << " production dynamic policy cases passed\n";
}
