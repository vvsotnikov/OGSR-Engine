cmake_minimum_required(VERSION 3.19)
project(dynamic-policy-test LANGUAGES CXX)
find_package(Python3 REQUIRED COMPONENTS Interpreter)
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS
    "${CMAKE_CURRENT_SOURCE_DIR}/../../../ogsr_engine/xrGame/alife_dynamic_object.cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/Baseline.inc"
    "${CMAKE_CURRENT_SOURCE_DIR}/Generate.py")
execute_process(COMMAND "${Python3_EXECUTABLE}" -B "${CMAKE_CURRENT_SOURCE_DIR}/Generate.py"
    "${CMAKE_CURRENT_BINARY_DIR}/methods.inc" COMMAND_ERROR_IS_FATAL ANY)
enable_testing()
foreach(variant release debug)
    add_executable(dynamic-policy-${variant} DynamicPolicyTest.cpp)
    target_compile_features(dynamic-policy-${variant} PRIVATE cxx_std_17)
    target_include_directories(dynamic-policy-${variant} PRIVATE "${CMAKE_CURRENT_BINARY_DIR}")
    if(variant STREQUAL "debug")
        target_compile_definitions(dynamic-policy-${variant} PRIVATE DEBUG)
    endif()
    add_test(NAME dynamic-policy-${variant} COMMAND dynamic-policy-${variant})
endforeach()
