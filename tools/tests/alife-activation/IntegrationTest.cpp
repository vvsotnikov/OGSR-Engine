#include "../../../ogsr_engine/xrGame/alife_activation_queue.h"
#include <stdexcept>
ALifeActivationQueue* active_queue;
bool defer_activation;
#include <vector>
#include <iostream>
#define START_PROFILE(...)
#define STOP_PROFILE
#define VERIFY2(...)
struct CSE_ALifeDynamicObject
{
    unsigned ID = 7, ID_Parent = 0xffff;
    bool m_bOnline = false, allowed = true, keep = false, becomes_online = false;
    unsigned attempts = 0;
    std::vector<unsigned char> client_data{1, 2, 3};
    bool can_switch_online() const { return allowed; }
    bool keep_saved_data_anyway() const { return keep; }
    // Models virtual dispatch returning without activation, including empty/far groups.
    void try_switch_online() { ++attempts; if (defer_activation && allowed) active_queue->enqueue(ID); else m_bOnline = becomes_online; }
};
struct Manager { ALifeActivationQueue m_activation_queue; void try_switch_online(CSE_ALifeDynamicObject*); };
#include "online-method.inc"
int main()
{
    for (bool deferred : {false, true})
    for (bool attached : {false, true})
        for (bool allowed : {false, true})
            for (bool keep : {false, true})
                for (bool activates : {false, true})
                {
                    CSE_ALifeDynamicObject object;
                    object.ID_Parent = attached ? 1 : 0xffff;
                    object.allowed = allowed; object.keep = keep; object.becomes_online = activates;
                    Manager manager;
                    active_queue = &manager.m_activation_queue; defer_activation = deferred;
                    manager.m_activation_queue.enqueue(object.ID); // stale request must be cancelled on attachment/denial
                    manager.try_switch_online(&object);
                    const bool queued = !attached && deferred && allowed;
                    const bool clear = !attached && !queued && !activates && !keep;
                    if (manager.m_activation_queue.contains(object.ID) != queued) return 2;
                    if (object.client_data.empty() != clear || object.attempts != (attached ? 0u : 1u))
                    {
                        std::cerr << "client-data mismatch: attached=" << attached << " allowed=" << allowed << " keep=" << keep << " activates=" << activates << "\n";
                        return 1;
                    }
                }
    std::cout << "32 manager cleanup cases passed\n";
}
