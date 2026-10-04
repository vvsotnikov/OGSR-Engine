This opt-in experiment separates eligible activation requests from registry
visits. The default engine path remains synchronous. Queue length is bounded by
the u16 ID space; cancel/re-enqueue does not accumulate stale slots. ID reuse
inherits a slot but never a pointer: consumption rechecks the current object.

The queue belongs to the switch manager and is not saved. First traversal,
loading, actor, story and forced-online objects stay synchronous. Direct calls
to switch_online always execute immediately. Deferred consumption shares the
remaining switch budget, with one-attempt progress and a 32-attempt cap; a single
activation is indivisible. Callbacks must not reset or recursively drain the queue.

No measured gameplay benefit is established. The existing switch iterator already
has a budget; this draft is an experiment, not a proposed default or a replacement
for fixing its units. Use Tracy's ALife/activation_queue scope to compare actual
activation bursts before deciding whether to retain the experiment.
