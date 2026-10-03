cmake_minimum_required(VERSION 3.19)
project(reconciliation-test LANGUAGES CXX)
find_package(Python3 REQUIRED COMPONENTS Interpreter)
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS
    "${CMAKE_CURRENT_SOURCE_DIR}/../../../ogsr_engine/xrGame/alife_switch_manager.cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/Generate.py")
execute_process(COMMAND "${Python3_EXECUTABLE}" -B "${CMAKE_CURRENT_SOURCE_DIR}/Generate.py"
    "${CMAKE_CURRENT_BINARY_DIR}/methods.inc" COMMAND_ERROR_IS_FATAL ANY)
add_executable(reconciliation-test ReconciliationTest.cpp)
target_compile_features(reconciliation-test PRIVATE cxx_std_17)
target_include_directories(reconciliation-test PRIVATE "${CMAKE_CURRENT_BINARY_DIR}")
enable_testing()
add_test(NAME lifecycle-order-equivalence COMMAND reconciliation-test)
