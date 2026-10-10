# Integration invariants

Enrollment and execution ownership differ. The native action planner arbitrates
ordinary A-Life, combat, and Lua schemes; Rust may issue online movement or pickup
only while ordinary A-Life owns execution. The Lua bridge reports persistent
ownership from xr_logic's active section, not from a selected action ID: meet,
combat and state transitions alone must not strand an offline goal. Custom
binders with a different activity model must adapt that bridge. Uninitialized
binders report no observation, not a release. A missing bridge or invalid control
tag rejects enrollment and pauses existing goals conservatively; it must not
turn an unknown owner into permission to act or prevent saving the game. This
pause survives saving: repairing the bridge releases it only when the NPC is
online and a valid report confirms that no script section owns it.

A persistent script section cannot finish offline because Lua schemes do not
execute there. Its ownership survives saves and representation changes until
the script releases the section (`active = nil`). Planner-compatible ordinary
logic must therefore have no active section; a standing `walker` or `remark`
job deliberately retains control, even when it has nothing to do. Temporary
reactions end at the representation boundary; they do not claim persistent
script ownership.

Opt-in still requires a dedicated section and excludes story/group/smart-terrain
assignments. The shipped smart-terrain registration goes through the native
brain selector, which excludes planner sections before enrollment. Its Lua
spawn-time gulag setup reads that same native ID; it does not independently
assign a job. Custom scripts must respect that ownership boundary. Only enrolled NPCs retain
binder snapshots.
The separate NPC save chunk retains that Lua payload without retaining native
client memory, conditions or inventory-owner state, which can become stale while
offline. It is consumed before binder net_spawn, where the saved scheme is
activated. Its writer version must accompany it: a live server entity can still
report an older input version, which would misparse freshly saved dialog data.
ClientSave captures the same fallback before level-change autosaves: that path
does not call switch_offline. Normal online loads consume the fallback after
loading the standard client payload, so the binder is never loaded twice.
A queued client spawn can be cancelled before binder restoration. Its pending
snapshot must survive; unlike an online save copy, it cannot have gone stale
through later client updates. This distinction is transient, not a save field.
Capturing ownership during save must not advance goal time or issue actions.
Old binderless saves carry a marker so the newly enabled binder initializes
without parsing missing Lua data. This is not a migration of campaign jobs.

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

Visual memory can be squad-shared, restored, or populated fictitiously by combat
logic. Only a successful personal visibility update is a new sighting. Offline
execution consumes remembered sources; it has no visual discovery channel.
Repeated sightings of the same stationary item must not renew its trip or retry
budget. Reusing a memory slot for a different item is different information even
at the same position; the native binding supplies that identity distinction.

Waiting is not a request to refresh world knowledge: it also covers retry
cooldowns. Explicit `remember_supply` news can clear that cooldown; recurring
sightings of an unchanged source cannot. Cooldowns can elapse without a known position; unlike travel
stall timers, they make no inference about movement during that interval.

The C ABI is not a synchronization boundary. Current frame ordering runs script
updates before deferred A-Life work and joins that work before the next frame.
Calls on an agent must remain serialized if that ordering changes. Agent allocation belongs to Rust;
host buffers belong to C++. Neither side may free the other's allocations.

The host and Rust are rebuilt together; the C ABI is private, not a mod API.
Adding observation facts does not itself require a save-format change. Changing
persisted goal state does require a versioned loader. Bounded source memory may
forget old information to accept new observations, but cannot replace the active
trip binding; forgetting a source does not mean learning that its item is gone.

Command numbers span the NPC lifetime, including replacement activities. The
engine latches movement and asynchronous pickup by command, so restarting an
activity's counter could mistake old execution state for a new request.
