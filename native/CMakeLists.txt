# native/CMakeLists.txt —— GDExtension 脚手架（M1 不参与构建流程）
#
# 目标：
#   ifz_selftest   —— 纯 C++ 核心自检（不依赖 Godot，可在 CI 单独跑）
#   ifz_native     —— GDExtension 动态库（需 -DIFZ_BUILD_EXTENSION=ON 且提供 godot-cpp）
#
# 用法（核心自检）：
#   cmake -S native -B native/build -DIFZ_BUILD_EXTENSION=OFF
#   cmake --build native/build --config Release
#   ctest --test-dir native/build --output-on-failure
#
# 用法（GDExtension，需先编译 godot-cpp）：
#   cmake -S native -B native/build-ext -DIFZ_BUILD_EXTENSION=ON -DGODOT_CPP_DIR=D:/tools/godot-cpp
#   cmake --build native/build-ext --config Release
#   产物：native/bin/ifz_native.dll（与 ifz_native.gdextension 的路径一致）
#
# 注意：M1 未编译、未验证；godot-cpp 与 Godot 4.4.1 的 ABI 必须匹配（见 ADR 0002）。

cmake_minimum_required(VERSION 3.20)
project(ifz_native LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

option(IFZ_BUILD_EXTENSION "构建 Godot GDExtension（需要 godot-cpp）" OFF)
option(IFZ_BUILD_SELFTEST "构建纯 C++ 核心自检" ON)

set(IFZ_SRC ${CMAKE_CURRENT_SOURCE_DIR}/src/ifz_native.cpp)

# ---------------------------------------------------------------- 核心自检
if(IFZ_BUILD_SELFTEST)
	add_executable(ifz_selftest ${IFZ_SRC})
	target_compile_definitions(ifz_selftest PRIVATE IFZ_SELFTEST)
	if(MSVC)
		target_compile_options(ifz_selftest PRIVATE /W4 /utf-8)
	else()
		target_compile_options(ifz_selftest PRIVATE -Wall -Wextra -Wpedantic)
	endif()
	set_target_properties(ifz_selftest PROPERTIES OUTPUT_NAME "ifz_selftest")

	enable_testing()
	add_test(NAME ifz_selftest COMMAND ifz_selftest)
endif()

# ---------------------------------------------------------------- GDExtension
if(IFZ_BUILD_EXTENSION)
	if(NOT GODOT_CPP_DIR)
		message(FATAL_ERROR "IFZ_BUILD_EXTENSION=ON 需要 -DGODOT_CPP_DIR=<godot-cpp 源码目录>")
	endif()
	if(NOT EXISTS ${GODOT_CPP_DIR}/CMakeLists.txt)
		message(FATAL_ERROR "GODOT_CPP_DIR 不是 godot-cpp 源码目录：${GODOT_CPP_DIR}")
	endif()

	add_subdirectory(${GODOT_CPP_DIR} ${CMAKE_CURRENT_BINARY_DIR}/godot-cpp EXCLUDE_FROM_ALL)

	add_library(ifz_native SHARED ${IFZ_SRC})
	target_compile_definitions(ifz_native PRIVATE IFZ_WITH_GODOT_CPP)
	target_link_libraries(ifz_native PRIVATE godot-cpp)
	target_include_directories(ifz_native PRIVATE ${GODOT_CPP_DIR}/include)
	if(MSVC)
		target_compile_options(ifz_native PRIVATE /W4 /utf-8)
	else()
		target_compile_options(ifz_native PRIVATE -Wall -Wextra)
	endif()

	# 与 ifz_native.gdextension 的 res://native/bin/ifz_native.dll 保持一致
	set_target_properties(ifz_native PROPERTIES
		LIBRARY_OUTPUT_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/bin
		RUNTIME_OUTPUT_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/bin
		OUTPUT_NAME ifz_native
	)
endif()
