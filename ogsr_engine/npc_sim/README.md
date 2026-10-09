# NPC intentions

A plan belongs to a server NPC, not its temporary online object. The Rust core
receives observations and returns travel/collect/wait decisions. It cannot
access engine objects or mutate inventory. The C++ adapter executes through the
existing movement managers and ownership operations; only observed ownership
advances collection to the return journey.

`npc_planner = supply_trip` reserves a stalker section for this owner **from
spawn**, before a trip exists. Its normal client Lua binder and smart-terrain
selection are therefore disabled. Do not put this setting on campaign or generic
stalker sections. Ordinary sections retain their existing behavior. Enrolment
rejects story NPCs, group members, smart-terrain occupants and scripted control.
A failed or finished trip remains owned and idle; it does not silently rejoin
legacy jobs.

Engine object IDs can change during representation switches. Runtime bindings
use the server objects, while saves bind the Rust identity and intention to the
IDs in that same save. Removing an object clears these bindings before its
callbacks run. No Rust pointer or struct layout is serialized. Saves without the
optional NPC chunk contain no enrolled plans. A saved plan requires its section
to retain the opt-in setting; loading rejects a conflicting configuration instead
of allowing both the Lua binder and Rust planner to control the same NPC.

Calls on a plan must be serialized by the host. The core does not introduce a
worker or alter the engine scheduler. Allocation never crosses ownership: Rust
creates/destroys plans; the host owns observation, decision and save buffers.

The first behavior is an explicitly assigned trip to a known existing item, not
a needs model or autonomous resource discovery. Remote item changes are not
revealed until the NPC reaches the remembered destination. Mixed online/offline
pickup is rejected, rather than forcing either object's representation or
creating a replacement item. Combat and danger take priority through the native
stalker planner; they interrupt execution without replacing the trip.

## Running the native check

Use `tools/tests/alife-policy/runtime/Run-NpcTrip.ps1` with an existing validation
installation and a package whose `build.json` matches its executable. Scenarios
are `basic`, `interrupt`, `offline`, `switch`, `missing`, `death`, `save`, and
`resume`; pass the
completed save session as `-ResumeSession` for the last one. The runner creates a
private configuration and appdata directory. Its Lua driver only sets up and
observes the scenario: it never moves the NPC or awards the supply. The interruption
case changes the actor's position and hostility to stimulate native combat.

Rust tests run in the existing Cargo workspace and mandatory local validation.
Native gameplay checks require the original game assets and an available input
device; they are not replaced by the headless tests.
