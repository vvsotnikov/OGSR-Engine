# Scheduler invariants

Queue order determines which objects wait when the frame budget expires. Live
survivors must retain their relative order and precede objects requeued after
processing; sorting by deadline or swapping with the tail changes that behavior.

Equivalent scheduling behavior does not require identical callback counts per
frame. Lower queue-maintenance cost can permit more callbacks within the same
elapsed-time budget. A canceled slot carries no scheduling obligation, even if
its former deadline has not arrived.

Ordinary callback work consumes the elapsed-time budget even when it cancels
itself, rejects an update, or throws. Outside prefetch, once that budget is
exceeded, later callbacks must wait for another pass. A callback is indivisible,
so the budget cannot bound the duration of a single callback.

Cancellation of the current callback must prevent its requeue, rather than merely
remove its former queue entry. Re-registering the same object creates a later
scheduling obligation; it must not revive the canceled invocation.

A scheduler-initiated drop ends dispatch but leaves the owner responsible for
lifetime cleanup. A later unregister consumes that retirement once; a new
registration replaces it with a new scheduling obligation. Final engine shutdown
expects no surviving owners; remaining registrations indicate a lifetime leak.
Debug propagates callback exceptions to preserve the original crash context.
Release recovery does not imply support for recovering an entire aborted update.
