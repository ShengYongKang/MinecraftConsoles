cmake_minimum_required(VERSION 3.21)
project(ourera_mesher LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>DLL")

if(NOT DEFINED GODOT_CPP_DIR)
  message(FATAL_ERROR "Set GODOT_CPP_DIR to a built godot-cpp checkout.")
endif()

set(GODOT_CPP_DIR "${GODOT_CPP_DIR}" CACHE PATH "Path to godot-cpp")
add_subdirectory(${GODOT_CPP_DIR} godot-cpp-build)

add_library(ourera_mesher SHARED
  src/register_types.cpp
  src/greedy_mesher_native.cpp
)

target_include_directories(ourera_mesher PRIVATE
  ${CMAKE_CURRENT_SOURCE_DIR}/src
)

target_link_libraries(ourera_mesher PRIVATE godot-cpp)

target_compile_definitions(ourera_mesher PRIVATE NOMINMAX)

set_target_properties(ourera_mesher PROPERTIES
  OUTPUT_NAME "ourera_mesher.windows.$<IF:$<CONFIG:Debug>,template_debug,template_release>.x86_64"
  RUNTIME_OUTPUT_DIRECTORY_DEBUG "${CMAKE_CURRENT_SOURCE_DIR}/bin/windows"
  RUNTIME_OUTPUT_DIRECTORY_RELEASE "${CMAKE_CURRENT_SOURCE_DIR}/bin/windows"
)
