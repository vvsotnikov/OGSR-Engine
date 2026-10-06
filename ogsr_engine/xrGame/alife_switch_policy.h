#pragma once

namespace alife_switch_policy
{
// These are production switching sequences, shared by the engine and tests.
// Operations bind engine objects/registries without transferring their ownership.
// Distance comparisons deliberately keep their original > and <= forms: they
// are not complements for NaN. Whole-map mode must not evaluate distance at all.
template <class Operations>
void dynamic_online(Operations& op)
{
    if (op.schedulable())
    {
        if (!op.needs_update())
        {
            if (op.scheduled()) op.unschedule();
        }
        else if (!op.scheduled()) op.schedule();
    }
    if (!op.can_online())
    {
        op.report_rejection(false);
        if (!op.keep_data()) op.clear_data();
        return;
    }
    if (!op.can_offline())
    {
        op.switch_online();
        return;
    }
    if (op.distance_mode() && (op.actor_distance() > op.online_limit()))
    {
        op.report_rejection(true);
        if (!op.keep_data()) op.clear_data();
        return;
    }
    op.switch_online();
}

template <class Operations>
void dynamic_offline(Operations& op)
{
    if (!op.can_offline()) return;
    if (!op.can_online())
    {
        op.switch_offline();
        return;
    }
    if (!op.distance_mode() || (op.actor_distance() <= op.offline_limit())) return;
    op.switch_offline();
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
    op.verify_group();
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
