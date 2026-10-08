cmake_minimum_required(VERSION 3.19)
project(alife-policy-tests LANGUAGES C CXX)
find_package(Python3 REQUIRED COMPONENTS Interpreter)
enable_testing()
foreach(pair "dynamic-policy-test|DynamicPolicyTest.cpp" "group-policy-test|GroupTest.cpp" "online-cleanup-test|OnlineCleanupTest.cpp" "online-offline-group-test|OnlineOfflineGroupTest.cpp")
 string(REPLACE "|" ";" parts "${pair}")
 list(GET parts 0 target)
 list(GET parts 1 source)
 add_executable(${target} ${source})
 target_compile_features(${target} PRIVATE cxx_std_17)
 target_include_directories(${target} PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/../../../ogsr_engine/xrGame")
 add_test(NAME ${target} COMMAND ${target})
endforeach()
find_program(POWERSHELL NAMES pwsh powershell REQUIRED)
add_test(NAME policy-log-errors COMMAND "${POWERSHELL}" -NoProfile -File "${CMAKE_CURRENT_SOURCE_DIR}/runtime/Test-ValidationLog.ps1")

add_executable(policy-lua-runner "${CMAKE_CURRENT_SOURCE_DIR}/../../../ogsr_engine/LuaJIT/src/host/minilua.c")
if(NOT WIN32)
    target_link_libraries(policy-lua-runner PRIVATE m)
endif()
add_test(NAME policy-lua-harness COMMAND policy-lua-runner "${CMAKE_CURRENT_SOURCE_DIR}/runtime/Test-PolicyHarness.lua" "${CMAKE_CURRENT_SOURCE_DIR}/runtime")

add_test(NAME policy-evidence-reader COMMAND "${Python3_EXECUTABLE}" -B "${CMAKE_CURRENT_SOURCE_DIR}/runtime/Test-Regular.py")

add_test(NAME policy-package-manifest COMMAND "${POWERSHELL}" -NoProfile -File "${CMAKE_CURRENT_SOURCE_DIR}/runtime/Test-ValidationPackage.ps1")
add_test(NAME policy-session-preparation COMMAND "${POWERSHELL}" -NoProfile -File "${CMAKE_CURRENT_SOURCE_DIR}/runtime/Test-RegularRunner.ps1")

add_test(NAME policy-checkout-metadata COMMAND "${POWERSHELL}" -NoProfile -File "${CMAKE_CURRENT_SOURCE_DIR}/runtime/Test-CheckoutMetadata.ps1")
add_test(NAME policy-messages COMMAND "${POWERSHELL}" -NoProfile -File "${CMAKE_CURRENT_SOURCE_DIR}/runtime/Test-PolicyMessages.ps1")
add_test(NAME policy-group-preparation COMMAND "${POWERSHELL}" -NoProfile -File "${CMAKE_CURRENT_SOURCE_DIR}/runtime/Test-GroupRunner.ps1")

add_test(NAME policy-particle-preparation COMMAND "${POWERSHELL}" -NoProfile -File "${CMAKE_CURRENT_SOURCE_DIR}/runtime/Test-ParticleRunner.ps1")

add_test(NAME policy-dog-preparation COMMAND "${POWERSHELL}" -NoProfile -File "${CMAKE_CURRENT_SOURCE_DIR}/runtime/Test-DogRunner.ps1")
