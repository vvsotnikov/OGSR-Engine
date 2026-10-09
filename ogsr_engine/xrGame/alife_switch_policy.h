#pragma once

namespace alife_switch_policy
{
enum class Action { keep, activate, deactivate };
// Why an attempted representation change was kept. none accompanies a
// transition; whole_map retains an already-online object without distance reads.
enum class Rejection { none, permission, distance, whole_map };
struct Decision
{
    Action action;
    Rejection rejection;
};

// The policy receives this restricted view in production as well as tests.
// Registry, transition, trace and client-data operations are not exposed.
// This restricts the callable API, not side effects within virtual/Lua queries.
template <class Source>
class QueryView
{
    const Source& source;
public:
    explicit QueryView(const Source& value) : source(value) {}
    bool can_online() const { return source.can_online(); }
    bool can_offline() const { return source.can_offline(); }
    bool distance_mode() const { return source.distance_mode(); }
    float actor_distance() const { return source.actor_distance(); }
    float online_limit() const { return source.online_limit(); }
    float offline_limit() const { return source.offline_limit(); }
};

// Query only: callers own maintenance and transition side effects. Preserve
// virtual permission precedence and lazy distance reads; > and <= are not
// complements for NaN. Whole-map mode must never query distance.
template <class Queries>
Decision dynamic_online(const Queries& op)
{
    if (!op.can_online()) return {Action::keep, Rejection::permission};
    if (!op.can_offline()) return {Action::activate, Rejection::none};
    if (op.distance_mode() && (op.actor_distance() > op.online_limit()))
        return {Action::keep, Rejection::distance};
    return {Action::activate, Rejection::none};
}

template <class Queries>
Decision dynamic_offline(const Queries& op)
{
    if (!op.can_offline()) return {Action::keep, Rejection::permission};
    if (!op.can_online()) return {Action::deactivate, Rejection::none};
    if (!op.distance_mode()) return {Action::keep, Rejection::whole_map};
    if (op.actor_distance() <= op.offline_limit())
        return {Action::keep, Rejection::distance};
    return {Action::deactivate, Rejection::none};
}

}
