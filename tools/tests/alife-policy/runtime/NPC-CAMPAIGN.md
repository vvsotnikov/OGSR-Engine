# Campaign ownership handoff

The campaign scenario loads a save containing three ordinary Cordon farm jobs;
it does not call planner enrollment or inject remembered supply locations. The
seed scenario disables migration only in its isolated config so it can produce
that input using the current engine. It requires the local Bar baseline seed.

```powershell
./Run-NpcTrip.ps1 -InstallRoot $install -Package $package -Scenario campaign-seed
# Use the completed session path printed by the runner as $completedSeed.
./Run-NpcTrip.ps1 -InstallRoot $install -Package $package -Scenario campaign -CampaignSeedSession $completedSeed
```

The fixture grants the farm's campaign prerequisite and fills empty slots using
ordinary spawn APIs. Replacement tests use the real respawner's acceptance and
tracking, temporarily moving its origin to the farm to avoid cross-map travel.
Neither changes the shipped activation condition or spawn locations.

Ambient enemies are removed nearby and residents are protected while checking
persistence, including before readiness during precache. These runs do not
validate resident survival during unprotected startup. An explicit hostile-player
stimulus tests combat on a migrated
resident; protection is removed for the death/replacement test. Other native
combat scenarios cover sustained fighting and corpse search interruptions.
The player is moved away from the camp to keep greeting behavior from masking
movement, including after the fighter has chased the player. Online rest requires
A-Life planner control and physical proximity to home; a paused rest phase alone
is not evidence that the NPC resumed. Rest is checked with the player away;
this scenario does not establish resting behavior during a nearby greeting. The fixture waits for resident rest, displaces one resident and requires
a return before provoking combat and removing supplies. Real acquisitions must
lead back to rest, which must survive online and off-map reloads. Post-combat
recovery and return travel have separate deadlines: danger can retain control
before any homeward movement starts, as in the existing engine. Recovery and
return each get 60 seconds; a failed return still fails the test. Displacement
is an external test stimulus, not a planner destination command. Save IDs are
fixture bindings, not persistent simulation identities.

The replacement is teleported outside the admission radius and held there until
it is otherwise eligible across a retry. The runner requires a native radius
rejection for that same NPC. The fixture then moves it inside and checks its
stored planner home. This isolates the admission boundary; it does not claim
that every legacy patrol naturally crosses that boundary.
