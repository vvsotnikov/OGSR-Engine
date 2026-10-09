#pragma once

#include <cstdint>

namespace alife_representation
{
// Transient, object-owned state: never serialized or indexed by a reusable ID.
// Notifications invalidate immediately; execution stays at the ALife boundary.
struct State
{
    bool valid = false;
    std::uint32_t flags = 0;
    std::uint32_t decisions = 0;
    std::uint32_t reuses = 0;

    void invalidate() { valid = false; }

    bool needs_decision(bool audited, std::uint32_t current_flags)
    {
        if (audited && valid && flags == current_flags)
        {
            ++reuses;
            return false;
        }
        // Inspecting raw flags also catches Lua writes that bypass notifications.
        // Clear validity for compatibility visits, including offline/attached
        // objects, so returning to the audited path always evaluates once.
        valid = audited;
        flags = current_flags;
        ++decisions;
        return true;
    }
};
}
