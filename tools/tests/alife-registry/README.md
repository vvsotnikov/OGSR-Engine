Unregister callbacks can access peer objects regardless of registry ID order.
All objects must remain alive until every unregister callback has finished;
`CSE_ALifeMonsterAbstract::on_unregister` depends on this when detaching from its group.

Configure this directory with CMake, build, then run CTest. The fixture compiles
the production destructor; it needs CMake and a C++17 compiler, not game assets.
