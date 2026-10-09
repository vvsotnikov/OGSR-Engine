# NPC intentions

Rust owns arrival, knowledge use, pickup waiting and travel-failure policy. The
host reports world facts and elapsed time, projects navigation positions through
the engine, and executes movement/ownership commands. Remote supply facts are
consumed only at the remembered destination; own inventory is always observable.
The saved destination is a navigation point; the remembered physical item
position is stored separately. Online observations use the live client position;
the server item position may lag physics. Knowing the item is still there does not
imply
that the NPC is close enough to collect it.
A different game vertex on the same level does not prevent arrival.

`npc_planner = supply_trip` reserves a stalker section for this owner **from
spawn**, before a trip exists. Its entire client Lua binder and smart-terrain
selection are disabled, including binder-driven callbacks. Legacy dialog/trade
entry points are disabled too, because those scripts require binder state. Use a
dedicated experimental section, not a campaign or generic stalker section.
Ordinary sections retain their behavior. Enrolment rejects story NPCs, group
members, smart-terrain occupants, scripted control and destinations outside the
loaded level. Completed/failed trips remain owned and idle. Removing the opt-in
between sessions discards the saved plan and restores ordinary NPC control;
the native client save marks the absent Lua payload so a newly enabled binder
initializes instead of reading nonexistent script state. Corrupt save records
and dangling saved object references remain errors.

Engine IDs can change during representation switches. Runtime bindings use the
server objects; saves bind durable identities to IDs from that same save and
write plans in identity order. Removing an object clears bindings before its
callbacks run. Rust layouts and pointers are never persisted. The outer save
version describes engine bindings; the inner version describes Rust state.
Saves without the optional chunk contain no enrolled plans.

A command number identifies one phase execution. The host sends at most one
pickup event for that command. Displacement creates a new command, permitting a
retry; an already queued event can still complete and must be observed. After
reload, pending network requests are reissued only if ownership is not already
confirmed. Rust owns the timeout; neither combat nor a representation mismatch
charges it, including the first observation after either pause. Elapsed time
belongs to the interval before an observation, so its preceding interruption /
readiness state is saved too. Movement in any direction counts as progress;
offline graph-edge distance counts even while the server position is unchanged.
A transient failed path build is retried; sixty active seconds without movement
or with a persistently failed path ends travel. A separate thirty-minute active
trip deadline bounds oscillation even across phase changes. Failure reasons are
returned and saved for diagnosis and future replanning. A representation mismatch
or
unknown item/NPC position has its own five-minute active waiting bound. Fixed
switch
permissions can make a trip impossible; they do not turn a temporary mismatch
into immediate failure. Absolute engine clock values are never persisted.

Online spawning marks the plan interrupted before ordinary activity can run,
because combat can be selected without any previous ordinary action to finalize.
Representation changes also invalidate elapsed host time.

Calls on each plan must be serialized. The adapter runs in the existing game /
ALife update phases; it does not add a worker. Allocation never crosses ownership:
Rust creates/destroys plans; C++ owns observation, decision and save buffers.
Only `step` produces executable decisions; status queries are not commands.

The native runner is `tools/tests/alife-policy/runtime/Run-NpcTrip.ps1`. It uses a
private configuration and appdata directory, original game assets, a matching
`build.json` package and an available input device. Its Lua driver never moves
the NPC or awards inventory. Test setup may change actor position/hostility,
item representation or physics, or remove a resource. Use `-Mode distance` with
`-Scenario natural` to exercise radius switching without permission overrides.
Rust tests directly exercise the same core used by the game.
