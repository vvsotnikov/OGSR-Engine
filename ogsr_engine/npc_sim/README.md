# Integration invariants

`npc_planner = supply_trip` takes control from spawn, before a trip is assigned.
The legacy Lua binder also owns campaign callbacks and dialog/trade state, not
just task selection. Opt-in therefore requires a dedicated NPC section; applying
it to campaign sections would remove those unrelated behaviors. Restoring the
binder after removing opt-in must preserve native client state while allowing
script state to initialize without an old Lua payload.

Server positions are not authoritative for online item physics. Navigation must
use a reachable point, while pickup knowledge and reach must use the physical
item position. Offline NPC positions can also stay unchanged while movement
advances within a graph edge; position samples alone cannot establish a stall.

Engine IDs can change when objects switch representation. A saved ID is a
reference within that same save, not a durable NPC identity. Runtime bindings
must be removed before destruction callbacks can observe or reuse them.

An observation's elapsed time belongs to the preceding interval. Combat can
start immediately after spawning, before an ordinary action has run, so its
finalization callback cannot mark every interruption. A gap across spawning,
representation changes or reload is not evidence of uninterrupted travel or
pickup waiting.

A pickup request is asynchronous: changing intention does not cancel an already
queued ownership event. Actual ownership must remain authoritative even after
a command changes. A save does not preserve the engine's pending event queue,
so restoring an intention must not assume its old request is still in flight.

The C ABI is not a synchronization boundary. Calls on a plan must remain
serialized if simulation moves to workers. Plan allocation belongs to Rust;
host buffers belong to C++. Neither side may free the other's allocations.
