#include <stdexcept>
#include <vector>
#include <string>
#include <iostream>
using Log = std::vector<std::string>;
void check(bool ok) { if (!ok) throw std::runtime_error("lifecycle ordering mismatch"); }
struct CTimer { void Start() {} float GetElapsed_sec() { return 0.000001f; } };
struct CSE_ALifeDynamicObject
{
    bool m_bOnline, pre_redundant, post_redundant, sync_ok, flip_sync, flip_transition, become_redundant;
    bool evaluated = false, released = false;
    Log log;
    bool redundant()
    {
        check(!released); log.push_back("redundant");
        return evaluated ? post_redundant : pre_redundant;
    }
};
struct Operations
{
    void release(CSE_ALifeDynamicObject* p) { check(!p->released); p->log.push_back("release"); p->released = true; }
    bool synchronize_location(CSE_ALifeDynamicObject* p)
    {
        check(!p->released); p->log.push_back("sync");
        p->m_bOnline ^= p->flip_sync;
        return p->sync_ok;
    }
    void dispatch(CSE_ALifeDynamicObject* p, const char* name)
    {
        check(!p->released); p->log.push_back(name); p->evaluated = true;
        p->m_bOnline ^= p->flip_transition;
        p->post_redundant |= p->become_redundant;
    }
    void try_switch_online(CSE_ALifeDynamicObject* p) { dispatch(p, "online"); }
    void try_switch_offline(CSE_ALifeDynamicObject* p) { dispatch(p, "offline"); }
};
struct Baseline : Operations { void switch_object(CSE_ALifeDynamicObject*); };
struct Candidate : Operations
{
    bool m_reconcile_sample = false;
    unsigned m_reconcile_objects = 0;
    double m_reconcile_stage_ms[4] = {};
    bool maintain_before_switch(CSE_ALifeDynamicObject*);
    void evaluate_switch(CSE_ALifeDynamicObject*);
    void maintain_after_switch(CSE_ALifeDynamicObject*);
    void switch_object(CSE_ALifeDynamicObject*);
};
#include "methods.inc"
int main()
{
    for (unsigned mask = 0; mask < 128; ++mask)
        for (bool sampled : {false, true})
        {
            CSE_ALifeDynamicObject original{bool(mask&1), bool(mask&2), bool(mask&4), bool(mask&8), bool(mask&16), bool(mask&32), bool(mask&64)};
            auto candidate = original;
            Baseline{}.switch_object(&original);
            Candidate manager; manager.m_reconcile_sample = sampled;
            manager.switch_object(&candidate);
            check(original.log == candidate.log);
            check(original.m_bOnline == candidate.m_bOnline && original.released == candidate.released && original.evaluated == candidate.evaluated);
            check(manager.m_reconcile_objects == unsigned(sampled));
        }
    std::cout << "256 real-method ordering comparisons passed (sampled and unsampled)\n";
}
