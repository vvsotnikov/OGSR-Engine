#pragma once

#include "alife_switch_policy.h"

namespace alife_switch_lifecycle
{
template <class Operations>
void maintain_offline_schedule(Operations& op)
{
    if (!op.schedulable()) return;
    if (!op.needs_update())
    {
        if (op.scheduled()) op.unschedule();
    }
    else if (!op.scheduled()) op.schedule();
}

template <class Operations>
void dynamic_online(Operations& op)
{
    maintain_offline_schedule(op);
    // Maintenance can change virtual permissions: decide only afterwards.
    const auto decision = alife_switch_policy::dynamic_online(op);
    if (decision.action == alife_switch_policy::Action::activate)
        op.switch_online();
    else
    {
        op.report_rejection(decision.rejection == alife_switch_policy::Rejection::distance);
        if (!op.keep_data()) op.clear_data();
    }
}

template <class Operations>
void dynamic_offline(Operations& op)
{
    if (alife_switch_policy::dynamic_offline(op).action == alife_switch_policy::Action::deactivate)
        op.switch_offline();
}

struct Unobserved
{
    void finished(unsigned) const {}
};

// Release invalidates the object. Observers see phase boundaries only, never
// the object. Synchronization can change representation before virtual dispatch.
template <class Operations, class Observer>
void reconcile_object(Operations& op, Observer& observer)
{
    if (op.redundant())
    {
        op.release();
        observer.finished(0);
        return;
    }
    const bool ready = op.synchronize_location();
    observer.finished(0);
    if (!ready) return;
    const bool online = op.online();
    if (online) op.try_switch_offline();
    else op.try_switch_online();
    observer.finished(online ? 1 : 2);
    if (op.redundant()) op.release();
    observer.finished(3);
}
}
