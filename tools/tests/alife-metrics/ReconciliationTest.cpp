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
struct Candidate : Operations
{
    bool m_reconcile_sample = false;
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
            Log expected{"redundant"};
            bool released = original.pre_redundant;
            bool evaluated = false;
            bool online = original.m_bOnline;
            if (released) expected.push_back("release");
            else
            {
                expected.push_back("sync");
                online ^= original.flip_sync;
                if (original.sync_ok)
                {
                    evaluated = true;
                    expected.push_back(online ? "offline" : "online");
                    online ^= original.flip_transition;
                    expected.push_back("redundant");
                    released = original.post_redundant || original.become_redundant;
                    if (released) expected.push_back("release");
                }
            }
            Candidate manager; manager.m_reconcile_sample = sampled;
            manager.switch_object(&candidate);
            check(expected == candidate.log);
            check(online == candidate.m_bOnline && released == candidate.released && evaluated == candidate.evaluated);
        }
    std::cout << "256 real-method lifecycle invariant cases passed (sampled and unsampled)\n";
}
