cmake_minimum_required(VERSION 3.16.3)

project("Chemica")

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_BUILD_TYPE Debug)

add_executable("chemica" 
    "Source/Main.cpp" 
    "Source/Program.cpp" 
    "Source/Program.h" 
    "Source/Simulation.cpp" 
    "Source/Simulation.h"
    "Source/ImGuizmo.h"
    "Source/ImGuizmo.cpp"
) 

add_subdirectory("External/glfw")
add_subdirectory("External/glad")
add_subdirectory("External/imgui")
add_subdirectory("External/json-parser")

target_link_libraries("chemica"
    PUBLIC 
    "glfw"
    "glad"
    "imgui"
    "json-parser"
)

target_include_directories("chemica" PUBLIC "External/glm")
target_include_directories("chemica" PUBLIC "External/stb_image")