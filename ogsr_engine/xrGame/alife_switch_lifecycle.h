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
    const alife_switch_policy::QueryView<Operations> queries{op};
    const auto decision = alife_switch_policy::dynamic_online(queries);
    if (decision.action == alife_switch_policy::Action::activate)
        op.switch_online();
    else
    {
        op.report_rejection(decision.rejection);
        if (!op.keep_data()) op.clear_data();
    }
}

template <class Operations>
void dynamic_offline(Operations& op)
{
    const alife_switch_policy::QueryView<Operations> queries{op};
    if (alife_switch_policy::dynamic_offline(queries).action == alife_switch_policy::Action::deactivate)
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
    if (op.needs_representation_decision(online))
    {
        if (online) op.try_switch_offline();
        else op.try_switch_online();
    }
    observer.finished(online ? 1 : 2);
    if (op.redundant()) op.release();
    observer.finished(3);
}

template <class Operations>
void manager_online(Operations& op)
{
    if (op.attached())
    {
        op.verify_parent();
        return;
    }
    op.verify_offline();
    op.try_online();
    if (!op.online() && !op.keep_data()) op.clear_data();
}

template <class Operations>
void legacy_group_offline(Operations& op)
{
    if (!op.size()) return;
    op.bind_group();
    unsigned i = 0;
    unsigned count = op.size();
    for (; i < count;)
    {
        auto member = op.monster(i);
        if (!member) { ++i; continue; }
        if (op.alive(member))
        {
            if (!op.can_offline(member)) { ++i; continue; }
            if (!op.can_online(member)) break;
            if (!op.distance_mode() || (op.actor_distance(member) <= op.offline_limit())) break;
            ++i;
            continue;
        }
        op.mark_dead(member);
        op.set_direct_control(member);
        op.erase_member(i);
        op.set_online(member, false);
        op.detach_if_attached(member);
        op.register_member(member);
        op.remove_graph_if_unattached(member);
        op.set_online(member, true);
        op.decrement_count();
        --count;
        // Erasing shifts the next member into i. A blocking live member stops
        // cleanup of subsequent corpses, even if group permission forces offline.
    }
    if (!op.size() || !op.can_offline()) return;
    // Inherited behavior, not the desired whole-map contract: #18 tracks the
    // legacy flesh-group retention defect separately from this refactor.
    if (op.can_online() || i == count) op.switch_offline();
}

template <class Operations>
void online_group_online(Operations& op)
{
    if (op.members().empty() || !op.can_online()) return;
    if (!op.can_offline())
    {
        op.select_actor_position();
        op.dynamic_online();
        return;
    }
    for (const auto& member : op.members())
    {
        op.verify_online_member(member);
        if (op.distance_mode() && (op.actor_distance(member) > op.offline_limit())) continue;
        op.select_member_position(member);
        op.dynamic_online();
        return; // First accepted member wins, even within the hysteresis band.
    }
}

template <class Operations>
void online_group_offline(Operations& op)
{
    if (op.members().empty() || !op.can_offline()) return;
    if (!op.can_online())
    {
        op.switch_offline();
        return;
    }
    for (const auto& member : op.members())
    {
        op.verify_offline_member(member);
        if (!op.distance_mode() || (op.actor_distance(member) <= op.offline_limit())) return;
    }
    op.switch_offline();
}
}
