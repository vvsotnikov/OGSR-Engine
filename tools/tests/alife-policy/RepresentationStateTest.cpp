#include "alife_representation_state.h"
#include <iostream>
#include <optional>
#include <stdexcept>

void require(bool value, const char* message)
{
    if (!value) throw std::runtime_error(message);
}

int main()
{
    try
    {
        std::optional<alife_representation::State> object{std::in_place};
        require(object->needs_decision(true, 6), "New object must evaluate");
        require(!object->needs_decision(true, 6), "Unchanged audited object must reuse");
        object->invalidate();
        object->invalidate();
        require(object->needs_decision(true, 6), "Notifications must force evaluation");
        require(!object->needs_decision(true, 6), "Duplicate notifications must coalesce");
        require(object->needs_decision(true, 4), "Unnotified raw flag write must evaluate");
        require(!object->needs_decision(true, 4), "New flag state must become reusable");
        require(object->needs_decision(false, 4), "Compatibility object must evaluate");
        require(object->needs_decision(false, 4), "Compatibility object must keep evaluating");
        require(object->needs_decision(true, 4), "Returning from compatibility must evaluate");
        require(!object->needs_decision(true, 4), "Audited path must resume reuse");
        require(object->decisions == 6 && object->reuses == 4, "Incorrect decision counters");
        object->invalidate();
        object.reset();
        object.emplace(); // Reusing the same storage/engine ID cannot inherit pending state.
        require(object->needs_decision(true, 4), "Replacement must not inherit cached decision");
        require(object->decisions == 1 && object->reuses == 0, "Counters must belong to the new lifetime");
    }
    catch (const std::exception& error) { std::cerr << error.what() << '\n'; return 1; }
    std::cout << "Production representation invalidation and lifetime cases passed\n";
}
