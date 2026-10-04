cmake_minimum_required(VERSION 3.19)
project(alife-policy-tests LANGUAGES CXX)
find_package(Python3 REQUIRED COMPONENTS Interpreter)
enable_testing()
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS
 "${CMAKE_CURRENT_SOURCE_DIR}/../../../ogsr_engine/xrGame/alife_dynamic_object.cpp"
 "${CMAKE_CURRENT_SOURCE_DIR}/../../../ogsr_engine/xrGame/alife_group_abstract.cpp"
 "${CMAKE_CURRENT_SOURCE_DIR}/../../../ogsr_engine/xrGame/alife_switch_manager.cpp"
 "${CMAKE_CURRENT_SOURCE_DIR}/../../../ogsr_engine/xrGame/alife_online_offline_group.cpp"
 "${CMAKE_CURRENT_SOURCE_DIR}/Generate.py")
execute_process(COMMAND "${Python3_EXECUTABLE}" -B "${CMAKE_CURRENT_SOURCE_DIR}/Generate.py"
 "${CMAKE_CURRENT_BINARY_DIR}/methods.inc" "${CMAKE_CURRENT_BINARY_DIR}/group-methods.inc" "${CMAKE_CURRENT_BINARY_DIR}/online-method.inc" "${CMAKE_CURRENT_BINARY_DIR}/online-offline-group-methods.inc" COMMAND_ERROR_IS_FATAL ANY)
foreach(pair "dynamic-policy-test|DynamicPolicyTest.cpp" "group-policy-test|GroupTest.cpp" "online-cleanup-test|OnlineCleanupTest.cpp" "online-offline-group-test|OnlineOfflineGroupTest.cpp")
 string(REPLACE "|" ";" parts "${pair}")
 list(GET parts 0 target)
 list(GET parts 1 source)
 add_executable(${target} ${source})
 target_compile_features(${target} PRIVATE cxx_std_17)
 target_include_directories(${target} PRIVATE "${CMAKE_CURRENT_BINARY_DIR}")
 add_test(NAME ${target} COMMAND ${target})
endforeach()
add_executable(dynamic-policy-debug DynamicPolicyTest.cpp)
target_compile_features(dynamic-policy-debug PRIVATE cxx_std_17)
target_compile_definitions(dynamic-policy-debug PRIVATE DEBUG)
target_include_directories(dynamic-policy-debug PRIVATE "${CMAKE_CURRENT_BINARY_DIR}")
add_test(NAME dynamic-policy-debug COMMAND dynamic-policy-debug)
