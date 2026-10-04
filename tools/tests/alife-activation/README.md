This opt-in experiment tests whether deferring expensive online switches lets
registry checks reach other objects sooner, at the cost of activation latency.
It does not establish that sweep stalls are a measured gameplay problem.

The default path remains synchronous. First traversal, loading, actor, story and
forced-online objects retain immediate semantics. Direct switch_online calls
always execute immediately. The queue is transient switch-manager state and is
not saved; the first traversal of a new level clears it.

At most one FIFO slot exists per u16 ID. Cancellation/re-enqueue cannot accumulate
stale slots. A reused ID inherits its position but never a pointer: consumption
resolves the current object and repeats normal eligibility and location checks.
That re-evaluation adds work. Leaving the level registry does not itself make
saved client data invalid, so a skipped request does not erase it.

Drain uses the iterator's own expiry predicate and clock, not a second allowance.
It attempts at least one queued slot and at most 32; one activation is indivisible.
On main's inflated allowance, the cap normally dominates. With corrected short
budgets, a traversal that exhausts the allowance leaves only the progress attempt.
Measurements across those base versions are not directly comparable. The queued
request plot may include released IDs until they are consumed; it is not a count
of live NPCs. Consumers must not reset the world or recursively drain the queue.

No gameplay benefit is established. Before adopting the experiment, compare
registry revisit latency, updates-to-online, and frame cost under the same engine
budget, including the cost of rechecking deferred objects.
