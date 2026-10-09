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

Removing an item's runtime binding is not news delivered to the NPC. Remembered
sources must survive that removal so absence is learned on a visit. Conversely,
inventory ownership is immediately available to the owner in both representations;
client inventory replication can lag the authoritative server ownership.

Waiting is not a request to refresh world knowledge: it also covers retry
cooldowns. Re-reporting a source is an explicit new observation and can clear
that cooldown. Cooldowns can elapse without a known position; unlike travel
stall timers, they make no inference about movement during that interval.

The C ABI is not a synchronization boundary. Current frame ordering runs script
updates before deferred A-Life work and joins that work before the next frame.
Calls on an agent must remain serialized if that ordering changes. Agent allocation belongs to Rust;
host buffers belong to C++. Neither side may free the other's allocations.
