Unregister callbacks can access peer objects regardless of registry ID order.
All objects must remain alive until every unregister callback has finished;
`CSE_ALifeMonsterAbstract::on_unregister` depends on this when detaching from its group.

Simulator unload sets `is_unloading()` before destroying the object registry.
Member callbacks still detach group links. Graph and scheduler updates are skipped
to avoid bookkeeping that will be discarded after the object registry; these
registries remain alive during the callbacks, so this is not the lifetime fix.
Outside unload, removing a member must restore its independent graph/scheduler
registration before removing the empty group from the appropriate registry.

`cargo xtask validate` includes these fixtures and both native build configurations.
Configure this directory with CMake, build, then run CTest. The fixture compiles
the production destructor and member-unregister method; it needs CMake and a C++17
compiler, not game assets. The fixtures do not exercise the full simulator unload.
