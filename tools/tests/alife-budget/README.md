The level iterator compares elapsed seconds with its budget; the ALife setting
is in microseconds. The original expression subtracts an `update_monster_factor`
fraction, and conversion applies to the remaining budget as a whole. No separate
time reservation for scheduled work is enforced by this expression.

The usual fraction is in [0, 1). Even if the budget is already exhausted, each
nonempty update must advance at least once, subject to predicate eligibility.
The budget is cooperative: one object can take longer than it. First-update
traversal remains unbounded. A smaller budget increases revisit latency rather
than permanently starving the iterator.

Configure with CMake, build and run CTest; the fixtures compile the production
setter and iterator update method without requiring game assets.
