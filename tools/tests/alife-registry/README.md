Unregister callbacks can access peer objects regardless of registry ID order.
All objects must remain alive until every unregister callback has finished;
`CSE_ALifeMonsterAbstract::on_unregister` depends on this when detaching from its group.

Simulator unload sets `is_unloading()` before destroying the object registry.
Member callbacks must still detach group links, but must not repopulate or mutate
the graph and scheduler registries: those are discarded after the object registry.
Outside unload, removing a member must restore its independent graph/scheduler
registration before removing the empty group from the appropriate registry.

Configure this directory with CMake, build, then run CTest. The fixture compiles
the production destructor and member-unregister method; it needs CMake and a C++17
compiler, not game assets. The fixtures do not exercise the full simulator unload.
