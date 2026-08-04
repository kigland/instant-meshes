cmake_minimum_required(VERSION 3.14)
project(instant-meshes LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 14)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

if(APPLE)
  set(CMAKE_OSX_DEPLOYMENT_TARGET "13.0" CACHE STRING "Minimum macOS deployment target")
endif()

if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
  set(CMAKE_BUILD_TYPE Release CACHE STRING "Build type" FORCE)
endif()

# ---- Dependencies ----

option(USE_SYSTEM_TBB "Use system TBB instead of bundled (for modern Linux)" OFF)

# TBB
if(USE_SYSTEM_TBB OR NOT IS_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/ext/tbb")
  find_package(TBB REQUIRED)
  set(TBB_LIB TBB::tbb)
  set(TBB_INCLUDE_DIRS ${TBB_INCLUDE_DIRS})
else()
  option(TBB_BUILD_STATIC "Build static TBB" ON)
  option(TBB_BUILD_SHARED "Build shared TBB" OFF)
  option(TBB_BUILD_TBBMALLOC "Build TBB malloc" OFF)
  option(TBB_BUILD_TBBMALLOC_PROXY "Build TBB malloc proxy" OFF)
  option(TBB_BUILD_TESTS "Build TBB tests" OFF)
  add_subdirectory(ext/tbb ext_build/tbb)
  set(TBB_LIB tbb_static)
  set(TBB_INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/ext/tbb/include)
endif()

# Eigen (header-only, bundled from ext/half-aware location)
# The code expects Eigen in ext/nanogui/ext/eigen — we keep a copy under ext/eigen
if(NOT EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/ext/eigen/Eigen/Core")
  message(STATUS "Downloading Eigen...")
  file(DOWNLOAD
    "https://gitlab.com/libeigen/eigen/-/archive/3.4.0/eigen-3.4.0.tar.gz"
    "${CMAKE_BINARY_DIR}/eigen.tar.gz"
    STATUS download_status
  )
  list(GET download_status 0 status_code)
  if(NOT status_code EQUAL 0)
    message(FATAL_ERROR "Failed to download Eigen. Please place Eigen in ext/eigen/")
  endif()
  file(ARCHIVE_EXTRACT INPUT "${CMAKE_BINARY_DIR}/eigen.tar.gz"
       DESTINATION "${CMAKE_BINARY_DIR}")
  file(RENAME "${CMAKE_BINARY_DIR}/eigen-3.4.0" "${CMAKE_CURRENT_SOURCE_DIR}/ext/eigen")
endif()

set(CORE_INCLUDES
  ${CMAKE_CURRENT_SOURCE_DIR}/src
  ${CMAKE_CURRENT_SOURCE_DIR}/ext/dset
  ${CMAKE_CURRENT_SOURCE_DIR}/ext/half
  ${CMAKE_CURRENT_SOURCE_DIR}/ext/pcg32
  ${CMAKE_CURRENT_SOURCE_DIR}/ext/pss
  ${CMAKE_CURRENT_SOURCE_DIR}/ext/rply
  ${CMAKE_CURRENT_SOURCE_DIR}/ext/eigen
  ${TBB_INCLUDE_DIRS}
  ${CMAKE_CURRENT_SOURCE_DIR}/ext/cgltf
)

if(USE_SYSTEM_TBB)
  list(REMOVE_ITEM CORE_INCLUDES ${CMAKE_CURRENT_SOURCE_DIR}/ext/pss)
endif()

# ---- Core Algorithm Library ----

set(CORE_SRCS
  src/adjacency.cpp
  src/hierarchy.cpp
  src/field.cpp
  src/extract.cpp
  src/meshio.cpp
  src/meshstats.cpp
  src/normal.cpp
  src/subdivide.cpp
  src/dedge.cpp
  src/bvh.cpp
  src/reorder.cpp
  src/smoothcurve.cpp
  src/serializer.cpp
  src/cleanup.cpp
  ext/rply/rply.c
)

add_library(instantmeshes_core STATIC ${CORE_SRCS})
target_include_directories(instantmeshes_core PUBLIC ${CORE_INCLUDES})
target_link_libraries(instantmeshes_core PUBLIC ${TBB_LIB})
target_compile_definitions(instantmeshes_core PRIVATE __TBB_NO_IMPLICIT_LINKAGE)

if(USE_SYSTEM_TBB)
  target_compile_definitions(instantmeshes_core PRIVATE USE_SYSTEM_TBB=1)
endif()

if(APPLE)
  target_link_libraries(instantmeshes_core PUBLIC "-framework Foundation")
  target_compile_options(instantmeshes_core PRIVATE
    $<$<NOT:$<CXX_COMPILER_ID:MSVC>>:-Wno-int-in-bool-context -Wno-deprecated-copy -Wno-unused-parameter -Wno-gnu-anonymous-struct -Wno-c99-extensions -Wno-nested-anon-types>
  )
endif()

# ---- CLI Tool ----

add_executable(instantmeshes-cli src/cli/main.cpp)
target_include_directories(instantmeshes-cli PRIVATE ${CORE_INCLUDES})
target_link_libraries(instantmeshes-cli PRIVATE instantmeshes_core ${TBB_LIB})
target_compile_definitions(instantmeshes-cli PRIVATE __TBB_NO_IMPLICIT_LINKAGE)
target_compile_options(instantmeshes-cli PRIVATE
  $<$<NOT:$<CXX_COMPILER_ID:MSVC>>:-Wno-deprecated-declarations -Wno-int-in-bool-context -Wno-deprecated-copy -Wno-unused-parameter>
)

if(APPLE)
  target_link_libraries(instantmeshes-cli PRIVATE "-framework Foundation")
  set_target_properties(instantmeshes-cli PROPERTIES CXX_STANDARD 14)
  add_custom_command(TARGET instantmeshes-cli POST_BUILD
    COMMAND strip $<TARGET_FILE:instantmeshes-cli>)
endif()

if(WIN32)
  set_target_properties(instantmeshes-cli PROPERTIES
    MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
endif()

# ---- Install ----

install(TARGETS instantmeshes-cli RUNTIME DESTINATION bin)
install(TARGETS instantmeshes_core ARCHIVE DESTINATION lib)
install(DIRECTORY src/
  DESTINATION include/instantmeshes
  FILES_MATCHING PATTERN "*.h"
  PATTERN "cli" EXCLUDE
)
