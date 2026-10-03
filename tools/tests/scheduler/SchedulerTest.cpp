#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <iostream>
#include <string>
#include <vector>
#include <functional>
#include <stdexcept>
#include <set>
#define ENGINE_API
#ifdef DEBUG
#define VERIFY(value) check(bool(value), "VERIFY: " #value)
#else
#define VERIFY(...)
#endif
void check(bool value, const std::string& message);
#define R_ASSERT(value) check(bool(value), "R_ASSERT: " #value)
#define ZoneScoped
#define ZoneScopedN(...)
#define TRUE 1
#define FALSE 0
using u32 = uint32_t;
using BOOL = bool;
template <class T>
using xr_vector = std::vector<T>;
struct shared_str : std::string
{
    using std::string::string;
    const char* operator*() const { return c_str(); }
};
template <class T>
void clamp(T& value, T low, T high)
{
    value = std::clamp(value, low, high);
}
int iFloor(float value) { return int(std::floor(value)); }
template <class... Args>
void Msg(Args...)
{}
uint64_t clock_ms = 0;
struct CTimer
{
    uint64_t start;
    void Start() { start = clock_ms; }
    u32 GetElapsed_ms() const
    {
        return u32(clock_ms - start);
    }
};
struct Stat
{
    struct
    {
        void Begin() {}
        void End() {}
    } Sheduler;
    float fShedulerLoad;
} statistics;
struct
{
    u32 dwTimeGlobal = 0, dwPrecacheFrame = 0;
    Stat* Statistic = &statistics;
} Device;
struct ISheduled
{
    struct
    {
        u32 t_min = 100, t_max = 250;
        bool b_RT = false, b_locked = false;
    } shedule;
    virtual ~ISheduled() = default;
    virtual float shedule_Scale() = 0;
    virtual void shedule_Update(u32) = 0;
    virtual shared_str shedule_Name() const { return "fixture"; }
    virtual bool shedule_Needed() = 0;
};
#define private public
#include "scheduler-under-test.h"
#undef private
#include "scheduler-under-test.cpp"

unsigned failures = 0;
std::string context;
void check(bool value, const std::string& message)
{
    if (!value)
    {
        ++failures;
        if (failures < 20)
            std::cerr << context << " " << message << "\n";
    }
}
struct NPC : ISheduled
{
    int id;
    float scale = 0;
    bool needed = true;
    bool throwNeeded = false, throwUpdate = false;
    u32 cost = 0, neededCalls = 0;
    std::vector<u32> elapsed;
    std::function<void()> action;
    std::function<void()> neededAction;
    std::function<void()> scaleAction;
    std::vector<int>* calls;
    NPC(int id, std::vector<int>& calls) : id(id), calls(&calls) {}
    float shedule_Scale() override
    {
        if (scaleAction)
            scaleAction();
        return scale;
    }
    bool shedule_Needed() override
    {
        ++neededCalls;
        if (neededAction)
            neededAction();
        if (throwNeeded)
            throw std::runtime_error("needed");
        return needed;
    }
    void shedule_Update(u32 dt) override
    {
        calls->push_back(id);
        elapsed.push_back(dt);
        clock_ms += cost;
        if (throwUpdate)
            throw std::runtime_error("update");
        if (action)
            action();
    }
};
struct World
{
    CSheduler scheduler;
    std::vector<int> calls;
    World()
    {
        Device.dwTimeGlobal = 0;
        Device.dwPrecacheFrame = 0;
        clock_ms = 0;
        psShedulerCurrent = 10;
        psShedulerTarget = 10;
        psShedulerMax = 10;
        scheduler.Initialize();
    }
    ~World() { scheduler.Destroy(); }
    void add(NPC& npc, u32 due = 0, u32 last = 0)
    {
        scheduler.Register(&npc);
        scheduler.internal_Registration();
        auto& entry = scheduler.Items.back();
        entry.dwTimeForExecute = due;
        entry.dwTimeOfLastExecute = last;
    }
    void tick(u32 time)
    {
        Device.dwTimeGlobal = time;
        scheduler.Update();
    }
    void order(std::initializer_list<int> expected)
    {
        std::vector<int> ids;
        for (auto& entry : scheduler.Items)
        {
            if (!entry.Object)
                continue;
            ids.push_back(static_cast<NPC*>(entry.Object)->id);
        }
        check(ids == std::vector<int>(expected), "unexpected live queue order");
    }
};
void ordering()
{
    World w;
    NPC a(1, w.calls), b(2, w.calls), c(3, w.calls), d(4, w.calls);
    w.add(a, 100);
    w.add(b, 0);
    w.add(c, 200);
    w.add(d, 0);
    w.tick(100);
    check(w.calls == std::vector<int>({2, 4}), "only strictly overdue entries dispatch, in queue order");
    check(a.neededCalls == 0 && c.neededCalls == 0, "future entries must not query needed");
    w.order({1, 3, 2, 4});
    w.scheduler.Unregister(&c, true); // Check live ordering after cancellation; slot removal is tested by compaction().
    w.calls.clear();
    w.tick(101);
    check(w.calls == std::vector<int>({1}), "deadline equality and canceled future item");
    w.order({2, 4, 1});
}
void compaction()
{
    World w;
    NPC a(1, w.calls);
    w.add(a, 200);
    w.scheduler.Unregister(&a, true);
    w.tick(100);
    check(w.scheduler.Items.empty(), "future tombstone must be removed immediately");
}
void intervals()
{
    struct Case
    {
        u32 low, high, last;
        float scale;
        u32 interval, elapsed;
    };
    // Explicit examples of the engine's derived bounds, not [t_min,t_max].
    const Case cases[] = {{100, 250, 0, 0, 100, 1000}, {100, 250, 0, 0.5f, 362, 1000}, {100, 250, 0, 1, 625, 1000},
                          {100, 250, 0, 2, 625, 1000}, {0, 0, 2000, 0, 30, 1},         {100, 2000, 0, 1, 1500, 2000}};
    for (auto c : cases)
    {
        World w;
        NPC a(1, w.calls);
        a.shedule.t_min = c.low;
        a.shedule.t_max = c.high;
        a.scale = c.scale;
        w.add(a, 0, c.last);
        w.tick(2000);
        check(a.elapsed == std::vector<u32>({c.elapsed}), "callback elapsed clamp");
        auto& entry = w.scheduler.Items.at(0);
        check(entry.dwTimeForExecute == 2000 + c.interval, "derived interval / scale clamp / floor");
        check(entry.dwTimeOfLastExecute == 2000, "last execution time");
    }
}
void budget()
{
    {
        World w;
        NPC a(1, w.calls), b(2, w.calls), c(3, w.calls);
        a.cost = 10;
        b.cost = 1;
        w.add(a);
        w.add(b);
        w.add(c);
        w.tick(100);
        check(w.calls == std::vector<int>({1, 2}), "budget is checked after dispatch and breaks strictly above limit");
        w.order({3, 1, 2});
        check(psShedulerTarget == 10 && psShedulerCurrent == 10, "over-budget target clamps at maximum");
        w.calls.clear();
        w.tick(101);
        check(w.calls == std::vector<int>({3}), "unprocessed tail gets next turn");
        check(psShedulerTarget == 9 && std::abs(psShedulerCurrent - 9.9f) < 0.001f, "under-budget adaptation");
    }
    {
        World x;
        NPC d(4, x.calls), e(5, x.calls);
        d.cost = 4;
        psShedulerCurrent = 3.9f;
        psShedulerTarget = 4;
        x.add(d);
        x.add(e);
        x.tick(100);
        check(x.calls == std::vector<int>({4}), "budget threshold uses floor");
        check(psShedulerTarget == 7 && std::abs(psShedulerCurrent - 4.21f) < 0.001f, "over-budget target increase and smoothing");
    }
}
void prefetch()
{
    World w;
    NPC a(1, w.calls), b(2, w.calls);
    a.cost = 50;
    b.cost = 50;
    w.add(a);
    w.add(b);
    Device.dwPrecacheFrame = 1;
    w.tick(100);
    check(w.calls == std::vector<int>({1, 2}), "precache bypasses time budget");
    check(psShedulerTarget == 9, "completed precache pass decreases target");
    w.order({1, 2});
}
void needed()
{
    World w;
    NPC a(1, w.calls), b(2, w.calls);
    a.needed = false;
    w.add(a);
    w.add(b);
    w.tick(100);
    w.tick(201);
    check(a.neededCalls == 1 && a.elapsed.empty(), "not-needed item is removed without callback");
    check(w.calls == std::vector<int>({2, 2}), "other item survives needed rejection");
    w.order({2});
}
void self_remove()
{
    for (bool again : {false, true})
    {
        World w;
        NPC a(1, w.calls), b(2, w.calls);
        a.action = [&] {
            w.scheduler.Unregister(&a);
            if (again)
                w.scheduler.Register(&a);
        };
        w.add(a);
        w.add(b);
        w.tick(100);
        check(w.calls == std::vector<int>({1, 2}), "self removal does not skip neighbor or dispatch registration immediately");
        if (again)
            w.order({2, 1});
        else
            w.order({2});
        a.action = {};
        w.calls.clear();
        w.tick(101);
        check(w.calls == (again ? std::vector<int>{1} : std::vector<int>{}), "self removal / re-registration next pass");
    }
}
void remove_other()
{
    World w;
    NPC a(1, w.calls), b(2, w.calls), c(3, w.calls);
    a.action = [&] { w.scheduler.Unregister(&b); };
    c.action = [&] { w.scheduler.Unregister(&a); }; // Already processed, so removal is deferred.
    w.add(a);
    w.add(b);
    w.add(c);
    w.tick(100);
    check(w.calls == std::vector<int>({1, 3}), "unregister later item suppresses callback");
    w.calls.clear();
    c.action = {};
    w.tick(201);
    check(w.calls == std::vector<int>({3}), "unregister earlier processed item prevents its next callback");
    w.order({3});
}
void registration()
{
    World w;
    NPC a(1, w.calls), b(2, w.calls), c(3, w.calls);
    w.scheduler.Register(&c);
    w.scheduler.Unregister(&c); // Paired pending operations cancel.
    w.add(a);
    a.action = [&] { w.scheduler.Register(&b); };
    w.tick(100);
    w.order({1, 2});
    check(w.calls == std::vector<int>({1}), "new registration is deferred until after dispatch");
    a.action = {};
    w.calls.clear();
    w.tick(101);
    check(w.calls == std::vector<int>({2}) && c.neededCalls == 0, "deferred and paired registrations");
    w.scheduler.Unregister(&b);
    w.calls.clear();
    w.tick(202);
    check(w.calls == std::vector<int>({1}), "external deferred unregister applies before dispatch");
}
void realtime()
{
    World w;
    NPC rt(9, w.calls), a(1, w.calls);
    w.scheduler.Register(&rt, true);
    w.add(a);
    w.tick(100);
    check(w.calls == std::vector<int>({9, 1}), "RT runs before ordinary callbacks");
    rt.needed = false;
    w.tick(150);
    rt.needed = true;
    w.tick(175);
    check(rt.elapsed == std::vector<u32>({100, 25}), "RT not-needed pass advances its last-update time");
    w.scheduler.Unregister(&rt, true);
    w.calls.clear();
    w.tick(180);
    check(w.calls.empty(), "external RT unregister removes callback");
}

void normal_cancels_rt()
{
    for (bool again : {false, true})
    {
        World w;
        NPC rt(1, w.calls), normal(2, w.calls);
        w.scheduler.Register(&rt, true);
        w.add(normal);
        normal.action = [&] {
            w.scheduler.Unregister(&rt);
            if (again)
                w.scheduler.Register(&rt, true);
        };
        w.tick(100);
        check(w.scheduler.ItemsRT.size() == (again ? 1u : 0u), "RT removals in normal phase compact in same tick");
        for (const auto& item : w.scheduler.ItemsRT)
            check(item.Object != nullptr, "no RT tombstones between updates");
        normal.action = {};
        w.calls.clear();
        w.tick(101);
        check(w.calls == (again ? std::vector<int>{1} : std::vector<int>{}), "RT cancellation and re-registration from normal phase");
    }
}
void needed_lifecycle()
{
    for (bool again : {false, true})
    {
        World w;
        NPC a(1, w.calls), b(2, w.calls);
        unsigned scales = 0;
        a.scaleAction = [&] { ++scales; };
        a.neededAction = [&] {
            w.scheduler.Unregister(&a);
            if (again)
                w.scheduler.Register(&a);
        };
        w.add(a);
        w.add(b);
        w.tick(100);
        check(scales == 0 && a.elapsed.empty(), "needed cancellation suppresses scale and update");
        check(w.calls == std::vector<int>{2}, "needed cancellation preserves neighbor dispatch");
        check(std::count_if(w.scheduler.Items.begin(), w.scheduler.Items.end(), [&](const auto& item) { return item.Object == &a; }) == (again ? 1 : 0),
              "needed cancellation leaves exactly the requested membership");
        a.neededAction = {};
        w.calls.clear();
        w.tick(101);
        check(w.calls == (again ? std::vector<int>{1} : std::vector<int>{}), "needed re-registration dispatches once on next pass");
    }
}

void callback_budget()
{
    for (bool prefetch : {false, true})
        for (int phase : {0, 1, 2})
            for (int outcome : {0, 1, 2, 3})
            {
                if (outcome == 3 && phase != 0)
                    continue;
                context = "phase=" + std::to_string(phase) + " outcome=" + std::to_string(outcome) + " prefetch=" + std::to_string(prefetch);
                World w;
                NPC a(1, w.calls), b(2, w.calls), c(3, w.calls);
                w.add(a);
                w.add(b);
                w.add(c);
                unsigned callbacks = 0;
                for (auto* npc : {&a, &b, &c})
                {
                    auto action = [&, npc] {
                        ++callbacks;
                        clock_ms += 100;
                        if (outcome == 2)
                            throw std::runtime_error("expensive callback");
                        if (outcome == 3)
                            npc->needed = false;
                        else
                        {
                            w.scheduler.Unregister(npc);
                            if (outcome == 1)
                                w.scheduler.Register(npc);
                        }
                    };
                    if (phase == 0)
                        npc->neededAction = action;
                    else if (phase == 1)
                        npc->scaleAction = action;
                    else
                        npc->action = action;
                }
                psShedulerMax = 100.f;
                Device.dwPrecacheFrame = prefetch ? 1 : 0;
                w.tick(100);
                check(callbacks == (prefetch ? 3u : 1u), "every callback exit honors budget except during prefetch");
                check(clock_ms == (prefetch ? 300u : 100u), "only one indivisible callback may overrun normal budget");
                if (!prefetch)
                {
                    check(b.neededCalls == 0 && c.neededCalls == 0, "budget stop leaves remaining objects untouched");
                    check(psShedulerTarget > 10.f, "canceled or failed work still counts as budget exhaustion");
                    if (outcome == 1)
                        w.order({2, 3, 1});
                    else
                        w.order({2, 3});
                    a.neededAction = {};
                    a.scaleAction = {};
                    a.action = {};
                    b.neededAction = {};
                    b.scaleAction = {};
                    b.action = {};
                    c.neededAction = {};
                    c.scaleAction = {};
                    c.action = {};
                    w.calls.clear();
                    w.tick(101);
                    check(w.calls == (outcome == 1 ? std::vector<int>{2, 3, 1} : std::vector<int>{2, 3}), "budget survivors run first on next pass");
                }
            }
    context.clear();
}

void scale_lifecycle()
{
    for (int mode : {0, 1, 2})
    {
        World w;
        NPC a(1, w.calls), b(2, w.calls);
        a.scaleAction = [&] {
#ifdef DEBUG
            check(w.scheduler.Registered(&a), "scale callback belongs to scheduler");
#endif
            if (mode == 2)
                throw std::runtime_error("scale");
            w.scheduler.Unregister(&a);
            if (mode == 1)
                w.scheduler.Register(&a);
        };
        w.add(a);
        w.add(b);
        w.tick(100);
        check(w.calls == std::vector<int>{2}, "canceled/throwing scale callback must not update");
        check(w.scheduler.m_current_step_obj == nullptr, "scale exit clears current callback");
        a.scaleAction = {};
        w.calls.clear();
        w.tick(101);
        check(w.calls == (mode == 1 ? std::vector<int>{1} : std::vector<int>{}), "scale re-registration deferred");
    }
}
#ifdef DEBUG
void registered_consistency()
{
    World w;
    NPC a(1, w.calls);
    w.add(a);
    w.scheduler.ItemsRT.push_back(w.scheduler.Items.front());
    unsigned before = failures;
    w.scheduler.Registered(&a);
    unsigned detected = failures - before;
    failures = before;
    check(detected > 0, "duplicate membership must assert");
    w.scheduler.ItemsRT.clear();
    w.scheduler.Items.clear();
    auto& operation = w.scheduler.Registration.emplace_back();
    operation.Object = &a;
    operation.OP = false;
    operation.RT = false;
    before = failures;
    w.scheduler.Registered(&a);
    detected = failures - before;
    failures = before;
    check(detected > 0, "unregister of absent object must assert");
    w.scheduler.Registration.clear();
}
#endif

void rt_mutation()
{
    for (int removed : {1, 2, 3})
    {
        for (bool again : {false, true})
        {
            World w;
            NPC a(1, w.calls), b(2, w.calls), c(3, w.calls);
            NPC* victim = removed == 1 ? &a : removed == 2 ? &b : &c;
            for (auto* npc : {&a, &b, &c})
                w.scheduler.Register(npc, true);
            b.action = [&] {
                w.scheduler.Unregister(victim);
                if (again)
                    w.scheduler.Register(victim, true);
            };
            w.tick(100);
            check(w.calls == (removed == 3 ? std::vector<int>{1, 2} : std::vector<int>{1, 2, 3}), "RT removal changes current-pass dispatch");
            check(w.scheduler.ItemsRT.size() == (again ? 3u : 2u), "RT removal/re-registration membership");
            b.action = {};
            w.calls.clear();
            w.tick(150);
            std::vector<int> expected;
            for (int id : {1, 2, 3})
                if (id != removed)
                    expected.push_back(id);
            if (again)
                expected.push_back(removed);
            check(w.calls == expected, "RT survivor and re-registration order");
            if (again)
                check(victim->elapsed.back() == 50, "RT re-registration timestamp");
        }
    }
    // A needed callback can unregister its own entry before Update dereferences it.
    World w;
    NPC a(1, w.calls), b(2, w.calls);
    w.scheduler.Register(&a, true);
    w.scheduler.Register(&b, true);
    a.neededAction = [&] { w.scheduler.Unregister(&a); };
    w.tick(100);
    check(w.calls == std::vector<int>{2}, "RT needed self-removal suppresses update");
    check(w.scheduler.ItemsRT.size() == 1, "RT needed removal compacts queue");
}

#ifdef DEBUG
void registered_state()
{
    World w;
    NPC a(1, w.calls), b(2, w.calls), c(3, w.calls);
    check(!w.scheduler.Registered(&a), "initially absent");
    w.scheduler.Register(&a);
    check(w.scheduler.Registered(&a), "pending registration visible");
    w.add(b);
    a.action = [&] { check(w.scheduler.Registered(&a), "current callback registered"); };
    b.action = [&] {
        check(w.scheduler.Registered(&a), "processed callback registered");
        w.scheduler.Unregister(&a);
        check(!w.scheduler.Registered(&a), "pending removal overrides processed membership");
        w.scheduler.Register(&c);
        check(w.scheduler.Registered(&c), "pending callback registration visible");
        w.scheduler.Unregister(&c);
        check(!w.scheduler.Registered(&c), "paired cancellation visible");
        w.scheduler.Unregister(&b);
        check(!w.scheduler.Registered(&b), "current callback removal visible");
    };
    w.tick(100);
    check(!w.scheduler.Registered(&a) && !w.scheduler.Registered(&b) && !w.scheduler.Registered(&c), "all removals applied");
    check(w.scheduler.m_debug_processed == nullptr, "temporary queue observer cleared");
}
#endif

void exception_cleanup()
{
    World w;
    NPC a(1, w.calls);
    a.throwUpdate = true;
    w.add(a);
    w.tick(100);
    check(w.scheduler.m_current_step_obj == nullptr, "exception leaves no current object");
    // A stale current pointer must not swallow cancellation of a pending registration.
    a.throwUpdate = false;
    w.scheduler.Register(&a);
    w.scheduler.Unregister(&a, true);
    w.calls.clear();
    w.tick(200);
    check(w.calls.empty() && w.scheduler.Items.empty(), "pending registration canceled after exception");
    w.scheduler.Register(&a);
    w.tick(201);
    w.tick(202);
    check(w.calls == std::vector<int>{1}, "object can register again after exception");
}

void exceptions()
{
    for (bool inNeeded : {true, false})
    {
        for (bool neighbor : {false, true})
        {
            World w;
            NPC a(1, w.calls), b(2, w.calls);
            a.throwNeeded = inNeeded;
            a.throwUpdate = !inNeeded;
            w.add(a);
            if (neighbor)
                w.add(b);
            w.tick(100);
            check(a.neededCalls == 1, "throwing object queried once");
            check(a.elapsed.size() == (inNeeded ? 0u : 1u), "exception callback count");
            if (neighbor)
            {
                w.order({2});
                check(b.elapsed.size() == 1, "neighbor dispatch after exception");
            }
            else
            {
                w.order({});
            }
            w.tick(201);
            check(a.neededCalls == 1, "throwing object must not be requeued");
            if (neighbor)
                check(b.elapsed.size() == 2, "neighbor survives exception");
        }
    }
}
void liveness()
{
    World w;
    std::vector<NPC> npcs;
    npcs.reserve(96);
    for (int id = 0; id < 96; ++id)
    {
        npcs.emplace_back(id, w.calls);
        npcs.back().cost = 11; // One callback consumes more than the maximum budget.
        w.add(npcs.back());
    }
    // With a fixed population, each overdue survivor must run within N passes.
    for (u32 round = 1; round <= 2; ++round)
    {
        for (u32 pass = 1; pass <= 96; ++pass)
            w.tick(((round - 1) * 96 + pass) * 1000);
        for (auto& npc : npcs)
            check(npc.elapsed.size() == round, "bounded dispatch progress id=" + std::to_string(npc.id));
    }
}

// Retained workload: 200 seeds, 96 objects, 100 frames; assertions replace digests.
struct StressNPC;
CSheduler* scheduler;
std::vector<StressNPC>* population;
u32 frame = 0, calls = 0, neededCount = 0, self_removals = 0, other_removals = 0, registrations = 0;
struct StressNPC : ISheduled
{
    u32 id, salt, updates = 0, lastFrame = ~0u;
    bool registered = true;
    StressNPC(u32 number, u32 seed) : id(number), salt(seed) {}
    float shedule_Scale() override { return float((id * 17 + salt) % 200) / 100.f; }
    bool shedule_Needed() override
    {
        ++neededCount;
        check(registered, "seed=" + std::to_string(salt) + " needed check after cancellation");
        if ((id + salt) % 31 == 0 && frame > 3)
        {
            if (!shedule.b_RT)
                registered = false;
            return false;
        }
        return true;
    }
    void shedule_Update(u32 dt) override
    {
        ++calls;
        ++updates;
        check(registered, "callback after cancellation");
        check(lastFrame != frame, "duplicate callback in one frame");
        lastFrame = frame;
        clock_ms += (id + salt + updates) % 4;
        if (shedule.b_RT)
            return;
        if ((id + updates + salt) % 19 == 0)
        {
            scheduler->Unregister(this, true);
            registered = false;
            ++self_removals;
            if (updates % 2 == 0)
            {
                scheduler->Register(this);
                registered = true;
                ++registrations;
            }
        }
        auto& other = population->at((id * 7 + salt + updates) % population->size());
        if (&other != this && other.registered && (id + updates) % 5 == 0)
        {
            scheduler->Unregister(&other, true);
            other.registered = false;
            ++other_removals;
        }
    }
};
void stress_test()
{
    for (u32 seed = 0; seed < 200; ++seed)
    {
        CSheduler instance;
        scheduler = &instance;
        instance.Initialize();
        std::vector<StressNPC> npcs;
        population = &npcs;
        npcs.reserve(96);
        psShedulerCurrent = 10;
        psShedulerTarget = 10;
        clock_ms = 0;
        for (u32 i = 0; i < 96; ++i)
        {
            npcs.emplace_back(i, seed);
        }
        Device.dwTimeGlobal = 0;
        for (auto& npc : npcs)
            instance.Register(&npc);
        for (frame = 0; frame < 100; ++frame)
        {
            context = "seed=" + std::to_string(seed) + " frame=" + std::to_string(frame);
            Device.dwTimeGlobal += 17 + (frame * 13 + seed) % 31;
            Device.dwPrecacheFrame = frame < 4 ? 1 : 0;
            // Include external forced unregister, deferred registration and RT work.
            if (frame == 8)
            {
                auto& npc = npcs[95];
                if (npc.registered)
                    instance.Unregister(&npc, true);
                instance.Register(&npc, true);
                npc.registered = true;
            }
            // Retire this RT participant; mutation cases are exercised by the focused tests.
            if (frame == 9)
            {
                if (npcs[95].registered)
                    instance.Unregister(&npcs[95], true);
                npcs[95].registered = false;
            }
            std::vector<ISheduled*> before;
            for (auto& item : instance.Items)
                if (item.Object)
                    before.push_back(item.Object);
            instance.Update();
            // Only compare surviving, unprocessed registrations. Processed objects
            // (including self-re-registration) are appended, not survivors.
            std::set<ISheduled*> survivors;
            std::vector<ISheduled*> after;
            for (auto& item : instance.Items)
                if (item.Object)
                {
                    auto& npc = *static_cast<StressNPC*>(item.Object);
                    if (npc.lastFrame != frame && std::find(before.begin(), before.end(), item.Object) != before.end())
                    {
                        survivors.insert(item.Object);
                        after.push_back(item.Object);
                    }
                }
            std::vector<ISheduled*> expected;
            for (auto* object : before)
                if (survivors.count(object))
                    expected.push_back(object);
            check(after == expected, "survivor order seed=" + std::to_string(seed) + " frame=" + std::to_string(frame));
            std::set<ISheduled*> live;
            for (auto& item : instance.Items)
                if (item.Object)
                {
                    auto& npc = *static_cast<StressNPC*>(item.Object);
                    check(npc.registered, "canceled object remains live after pass");
                    check(live.insert(&npc).second, "duplicate live queue entry");
                    if (npc.lastFrame == frame && item.dwTimeForExecute != Device.dwTimeGlobal)
                    {
                        check(item.dwTimeOfLastExecute == Device.dwTimeGlobal, "updated object timestamp");
                        check(item.dwTimeForExecute >= Device.dwTimeGlobal + 100 && item.dwTimeForExecute <= Device.dwTimeGlobal + 625, "derived interval bounds");
                    }
                }
            for (auto& item : instance.ItemsRT)
                check(live.insert(item.Object).second, "duplicate RT membership");
            for (auto& npc : npcs)
                check((live.count(&npc) != 0) == npc.registered,
                      "registration membership mismatch seed=" + std::to_string(seed) + " frame=" + std::to_string(frame) + " id=" + std::to_string(npc.id) +
                          " registered=" + std::to_string(npc.registered) + " live=" + std::to_string(live.count(&npc)));
        }
        instance.Destroy();
    }
    check(calls > 0 && neededCount > 0 && self_removals > 0 && other_removals > 0 && registrations > 0, "stress workload must exercise all interaction categories");
}

int main(int argc, char** argv)
{
    if (argc != 2)
        return 2;
    const std::string name = argv[1];
    try
    {
#ifdef DEBUG
        if (name == "registered_consistency")
        {
            registered_consistency();
            return failures ? 1 : 0;
        }
        if (name == "registered_state")
        {
            registered_state();
            return failures ? 1 : 0;
        }
#endif
        if (name == "needed_lifecycle")
            needed_lifecycle();
        else if (name == "callback_budget")
            callback_budget();
        else if (name == "normal_cancels_rt")
            normal_cancels_rt();
        else if (name == "scale_lifecycle")
            scale_lifecycle();
        else if (name == "exception_cleanup")
            exception_cleanup();
        else if (name == "rt_mutation")
            rt_mutation();
        else if (name == "ordering")
            ordering();
        else if (name == "compaction")
            compaction();
        else if (name == "exceptions")
            exceptions();
        else if (name == "liveness")
            liveness();
        else if (name == "intervals")
            intervals();
        else if (name == "budget")
            budget();
        else if (name == "prefetch")
            prefetch();
        else if (name == "needed")
            needed();
        else if (name == "self_remove")
            self_remove();
        else if (name == "remove_other")
            remove_other();
        else if (name == "registration")
            registration();
        else if (name == "realtime")
            realtime();
        else if (name == "stress")
            stress_test();
        else
            return 2;
    }
    catch (const std::exception& e)
    {
        std::cerr << e.what() << "\n";
        return 1;
    }
    if (failures)
    {
        std::cerr << name << ": " << failures << " failed assertions\n";
        return 1;
    }
    std::cout << name << ": passed\n";
}
