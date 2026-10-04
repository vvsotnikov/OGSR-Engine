cmake_minimum_required(VERSION 3.19)
project(ogsr-tests LANGUAGES CXX)
enable_testing()

# Every immediate child containing CMakeLists.txt is a required suite.
file(GLOB children CONFIGURE_DEPENDS RELATIVE "${CMAKE_CURRENT_SOURCE_DIR}" "*")
foreach(child IN LISTS children)
    if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/${child}/CMakeLists.txt")
        add_subdirectory("${child}")
    endif()
endforeach()
