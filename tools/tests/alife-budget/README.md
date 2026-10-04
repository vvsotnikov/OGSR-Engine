The level iterator compares its budget to elapsed seconds. The ALife setting is
in microseconds, with `update_monster_factor` reserving a fraction for scheduled
work; the conversion must apply to the remaining budget as a whole.

Configure with CMake, build and run CTest. The fixture compiles the production
setter against a graph that records the budget it receives.
