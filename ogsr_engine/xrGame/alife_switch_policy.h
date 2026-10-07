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
    // Distance-mode compatibility: group permission can override a live blocker.
    if (op.can_online() || i == count) op.switch_offline();
}

// A legacy group is a server-only owner. In whole-map mode each living
// member follows the intersection of its own and the group's permissions.
// Conflicting online/offline denials freeze the existing state, as for a
// standalone object. Unknown member types retain their existing state.
template <class Operations>
void legacy_group_whole_map(Operations& op)
{
    op.bind_group();
    op.prepare_members();
    bool any_online = false;
    for (unsigned i = 0; i < op.size();)
    {
        auto member = op.monster(i);
        if (!member)
        {
            any_online = any_online || op.online_at(i);
            ++i;
            continue;
        }
        if (!op.alive(member))
        {
            const bool was_online = op.online(member);
            op.mark_dead(member);
            op.set_direct_control(member);
            op.erase_member(i);
            op.set_online(member, false);
            op.detach_if_attached(member);
            op.register_member(member);
            if (was_online) op.remove_graph_if_unattached(member);
            op.set_online(member, was_online);
            op.decrement_count();
            continue;
        }
        const bool may_online = op.can_online() && op.can_online(member);
        const bool may_offline = op.can_offline() && op.can_offline(member);
        if (op.online(member))
        {
            if (may_offline && !may_online) op.deactivate(member);
        }
        else if (may_online)
        {
            // The container must enter its online registries before client spawn.
            op.group_online(true);
            op.activate(member, i);
        }
        any_online = any_online || op.online(member);
        ++i;
    }
    op.group_online(any_online);
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
