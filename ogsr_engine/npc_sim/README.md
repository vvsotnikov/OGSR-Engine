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

Dedicated planner sections bypass smart-terrain assignment from spawn. Campaign
migration instead waits for an allowlisted ordinary camp job to start, then
unregisters it through the existing camp API before installing idle binder logic.
Story/group assignments, exclusive jobs, spawn-specific logic and a different
active script section are not eligible. Profile and camp allowlists are both
required; sharing an NPC section alone is not permission to migrate it.

Migrated residents retain their home-camp reservation independently of legacy job
membership, including while off-map. Dead residents no longer consume capacity.
The Lua population counts remaining legacy jobs, not planner residents. The
shipped farm uses `general_lager`; its population-dependent state selects only
those remaining jobs. Its spawn data has capacity three and the
`agroprom_military_case` prerequisite; the installed SoC scripts/config contain
no farm-specific population/emptiness quest consumers. Other camps require the
same consumer audit before allowlisting. The installed `smart_terrain.script` method `se_smart_terrain:unregister_npc` removes
the gulag object, restores squad/group and clears the native smart-terrain ID;
`xr_gulag.script` owns `capacity_non_exclusive`, adjusted by `se_smart_terrain:preserve_exclusives`. The installed `se_respawn:create(prob)` returns acceptance and appends accepted IDs to `spawned_obj`.

Campaign residents choose supply acquisition ahead of camp residence only when
they lack a bandage and know an available source. Otherwise they return home and
rest; no source is invented to keep an unsupplied resident busy. Camp residence
is independent of possession, and shares travel execution without sharing supply
failure or retry history. Combat and persistent script ownership suspend it.
Rest has no travel deadline; displacement requires a new return command. Failed
returns back off across saves instead of retrying every frame. The native relaxed
standing animation executes rest; legacy camp jobs and seated routines are not
reactivated. Dedicated supply-only NPCs retain their old behavior.

The NPCG v7 snapshot distinguishes camp and supply execution; at most one may own
a command. Older campaign saves enable camp residence from their persisted camp
affiliation without discarding source knowledge or an active supply trip.
Each goal keeps the resident's own handoff position
as home only inside the configured `home_radius`; approach travel remains a
legacy job until then. A job that never enters that radius remains legacy: mixed
legacy/planner occupancy is supported, not evidence that every job was migrated.
It does not send the entire camp to its centre. Profile lists gate new
admission, not existing saved ownership; removing a profile does not silently
cancel its goal. Removing the whole camp section opts its saved residents out,
as removing a dedicated planner section does.

Legacy respawners still select and register a job before accepting a new spawn;
handoff happens after client activation so that acceptance is not bypassed.
Loaded planner ownership must suppress legacy job selection before the simulator
becomes globally active. Only enrolled NPCs retain binder snapshots.
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
without parsing missing Lua data. Campaign migration uses the separate ordinary-job handoff described above.

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
budget. Sightings refresh eviction recency without changing those budgets or
the remembered navigation point. Reusing a memory slot for a different item is
different information even at the same position; the native binding supplies
that identity distinction.

Waiting is not a request to refresh world knowledge: it also covers retry
cooldowns. Explicit `remember_supply` news can clear that cooldown; recurring
sightings of an unchanged source cannot. Cooldowns can elapse without a known
position; unlike travel stall timers, they make no inference about movement
during that interval.

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

Seeing a body establishes a possible search location, not knowledge of its
inventory. Only inspection at the body may enumerate its contents. Moving a
searched body or seeing it again does not reveal replenishment; exhausted-source
knowledge survives those sightings and save/reload until that source is evicted.
Known loose bandages take priority over body searches, then distance breaks ties.
Offline execution uses the
same remembered location and search result, without discovering unseen bodies.

Corpse looting commits authoritative server ownership before another NPC can
inspect the same inventory. Online reject/take packets replicate that transfer;
they are not two independent attempts to acquire a still-available item. A body
and its looter must share a representation. Corpses remain online on the loaded
map under the existing engine policy, so off-map inspection is validated through
an actual level transition, not by forcing only the looter offline.

Corpse searches skip statically untakeable items. Online searches respect native
inventory acceptance; offline searches use the ALife mass budget, which cannot
represent dynamic weapon weights or equipment bonuses. These are search rules;
loose-item pickup retains its existing engine path.
A body with only temporarily refused items is not known to be empty. Selection
must try other acceptable items before deferring the body. Backoff is per source:
one refusal does not establish that every other body holds equally heavy items.
A refusal ends the current attempt and retains the source with exponential retry
backoff, capped at fifteen minutes. Sightings, body movement and saves preserve
that backoff; a successful search resets it. A refusal
must not mark the body empty or hold execution until the trip deadline.
