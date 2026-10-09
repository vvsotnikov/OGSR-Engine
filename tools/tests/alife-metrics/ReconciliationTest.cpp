#include "alife_diagnostics.h"
#include "alife_switch_lifecycle.h"
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

void require(bool ok, const char* message) { if (!ok) throw std::runtime_error(message); }
struct TestTimer
{
    static unsigned constructions;
    unsigned reads = 0;
    TestTimer() { ++constructions; }
    void Start() { reads = 0; }
    double GetElapsed_sec() { const double times[] = {.002, .005, .009}; return times[reads++]; }
};
unsigned TestTimer::constructions = 0;

// Implements the operations interface; no engine class declarations are copied.
struct Operations
{
    bool initial_redundant = false, synchronized = true, is_online = false;
    bool flip_on_sync = false, flip_on_switch = false, redundant_after_switch = false;
    bool evaluated = false, released = false, redundant_after_sync = false, synchronized_once = false;
    unsigned online_reads = 0;
    bool decision_needed = true;
    bool needs_representation_decision(bool online) { alive(); require(synchronized_once && online == is_online, "Decision before synchronization"); return decision_needed; }
    std::vector<std::string> calls;
    void alive() const { require(!released, "Object accessed after release"); }
    bool redundant() { alive(); calls.push_back("redundant"); return (synchronized_once && redundant_after_sync) || (evaluated ? redundant_after_switch : initial_redundant); }
    void release() { alive(); calls.push_back("release"); released = true; }
    bool synchronize_location() { alive(); calls.push_back("sync"); is_online ^= flip_on_sync; synchronized_once = true; return synchronized; }
    bool online() { alive(); ++online_reads; return is_online; }
    void dispatch(const char* name) { alive(); calls.push_back(name); evaluated = true; is_online ^= flip_on_switch; }
    void try_switch_online() { dispatch("online"); }
    void try_switch_offline() { dispatch("offline"); }
};

void scenario(const char* name, Operations operations, const std::vector<std::string>& expected,
              int phase, bool release_expected, bool sampled)
{
    try
    {
        double stages[4] = {};
        const unsigned timers = TestTimer::constructions;
        if (sampled)
        {
            alife_diagnostics::ReconciliationTiming<TestTimer> timing(stages);
            alife_switch_lifecycle::reconcile_object(operations, timing);
        }
        else
        {
            alife_switch_lifecycle::Unobserved observer;
            alife_switch_lifecycle::reconcile_object(operations, observer);
        }
        require(operations.calls == expected, "Lifecycle operation order differs");
        require(operations.online_reads == unsigned(phase != 0), "Representation must be read once after synchronization");
        require(operations.released == release_expected, "Incorrect release outcome");
        require(TestTimer::constructions - timers == unsigned(sampled), "Unsampled path constructed a timer");
        require(stages[0] == (sampled ? 2.0 : 0.0), "Incorrect pre-switch duration");
        require(stages[1] == (sampled && phase == 1 ? 3.0 : 0.0), "Incorrect offline-attempt attribution");
        require(stages[2] == (sampled && phase == 2 ? 3.0 : 0.0), "Incorrect online-attempt attribution");
        require(stages[3] == (sampled && phase != 0 ? 4.0 : 0.0), "Incorrect post-switch duration");
    }
    catch (const std::exception& error)
    {
        throw std::runtime_error(std::string(name) + (sampled ? " (sampled): " : " (unsampled): ") + error.what());
    }
}

int main()
{
    try
    {
        for (bool sampled : {false, true})
        {
            Operations op;
            op.initial_redundant = true;
            scenario("early release", op, {"redundant", "release"}, 0, true, sampled);
            op = {}; op.synchronized = false;
            scenario("failed synchronization", op, {"redundant", "sync"}, 0, false, sampled);
            op = {};
            scenario("offline object", op, {"redundant", "sync", "online", "redundant"}, 2, false, sampled);
            op = {}; op.is_online = true;
            scenario("online object", op, {"redundant", "sync", "offline", "redundant"}, 1, false, sampled);
            op = {}; op.flip_on_sync = true;
            scenario("synchronization brings online", op, {"redundant", "sync", "offline", "redundant"}, 1, false, sampled);
            op = {}; op.is_online = true; op.flip_on_sync = true;
            scenario("synchronization takes offline", op, {"redundant", "sync", "online", "redundant"}, 2, false, sampled);
            op = {}; op.flip_on_switch = true;
            scenario("switch changes state", op, {"redundant", "sync", "online", "redundant"}, 2, false, sampled);
            op = {}; op.decision_needed = false;
            scenario("unchanged representation still maintains lifecycle", op, {"redundant", "sync", "redundant"}, 2, false, sampled);
            op = {}; op.decision_needed = false; op.redundant_after_sync = true;
            scenario("release after skipped decision", op, {"redundant", "sync", "redundant", "release"}, 2, true, sampled);
            op = {}; op.redundant_after_switch = true;
            scenario("post-switch release", op, {"redundant", "sync", "online", "redundant", "release"}, 2, true, sampled);
        }
    }
    catch (const std::exception& error) { std::cerr << error.what() << '\n'; return 1; }
    std::cout << "Production reconciliation ordering and timing cases passed\n";
}
