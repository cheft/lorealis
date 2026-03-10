cmake_minimum_required(VERSION 3.10)
cmake_policy(SET CMP0135 NEW)
project(lorealis)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

include(FetchContent)

# --- Build Optimization: Compiler Caching ---
find_program(SCCACHE_PROGRAM sccache)
find_program(CCACHE_PROGRAM ccache)
if(SCCACHE_PROGRAM)
    set(CMAKE_C_COMPILER_LAUNCHER "${SCCACHE_PROGRAM}")
    set(CMAKE_CXX_COMPILER_LAUNCHER "${SCCACHE_PROGRAM}")
    message(STATUS "--- Build Optimization: sccache ENABLED ---")
elseif(CCACHE_PROGRAM)
    set(CMAKE_C_COMPILER_LAUNCHER "${CCACHE_PROGRAM}")
    set(CMAKE_CXX_COMPILER_LAUNCHER "${CCACHE_PROGRAM}")
    message(STATUS "--- Build Optimization: ccache ENABLED ---")
endif()

# --- Lua and Sol2 Dependencies ---
set(SOL2_BUILD_TESTS OFF CACHE BOOL "" FORCE)

if(PLATFORM_SWITCH)
    # On Switch, use the system-provided Lua 5.1 from devkitPro
    message(STATUS "--- Using system Lua 5.1 for Switch ---")
    find_package(PkgConfig REQUIRED)
    pkg_check_modules(LUA REQUIRED lua51) # devkitPro switch portlibs uses lua51.pc
    
    set(LUA_LIBS ${LUA_LIBRARIES})
    set(LUA_INC ${LUA_INCLUDE_DIRS})
    set(SOL_LUA_VER 501)
else()
    # On Desktop, fetch Lua 5.1.5
    message(STATUS "--- Fetching Lua 5.1.5 for Desktop ---")
    FetchContent_Declare(
        lua_src
        URL "https://www.lua.org/ftp/lua-5.1.5.tar.gz"
        DOWNLOAD_EXTRACT_TIMESTAMP true
    )
    FetchContent_MakeAvailable(lua_src)
    
    # Lua 5.1 source files (in src/ subdirectory)
    set(LUA_SRC_DIR ${lua_src_SOURCE_DIR}/src)
    set(LUA_SOURCES
        ${LUA_SRC_DIR}/lapi.c
        ${LUA_SRC_DIR}/lcode.c
        ${LUA_SRC_DIR}/ldebug.c
        ${LUA_SRC_DIR}/ldo.c
        ${LUA_SRC_DIR}/ldump.c
        ${LUA_SRC_DIR}/lfunc.c
        ${LUA_SRC_DIR}/lgc.c
        ${LUA_SRC_DIR}/llex.c
        ${LUA_SRC_DIR}/lmem.c
        ${LUA_SRC_DIR}/lobject.c
        ${LUA_SRC_DIR}/lopcodes.c
        ${LUA_SRC_DIR}/lparser.c
        ${LUA_SRC_DIR}/lstate.c
        ${LUA_SRC_DIR}/lstring.c
        ${LUA_SRC_DIR}/ltable.c
        ${LUA_SRC_DIR}/ltm.c
        ${LUA_SRC_DIR}/lundump.c
        ${LUA_SRC_DIR}/lvm.c
        ${LUA_SRC_DIR}/lzio.c
        ${LUA_SRC_DIR}/lauxlib.c
        ${LUA_SRC_DIR}/lbaselib.c
        ${LUA_SRC_DIR}/ldblib.c
        ${LUA_SRC_DIR}/liolib.c
        ${LUA_SRC_DIR}/lmathlib.c
        ${LUA_SRC_DIR}/loslib.c
        ${LUA_SRC_DIR}/ltablib.c
        ${LUA_SRC_DIR}/lstrlib.c
        ${LUA_SRC_DIR}/loadlib.c
        ${LUA_SRC_DIR}/linit.c
    )
    add_library(liblua STATIC ${LUA_SOURCES})
    target_include_directories(liblua PUBLIC ${LUA_SRC_DIR})
    
    # Create lua.hpp for Lua 5.1 (needed by sol2)
    if(NOT EXISTS ${LUA_SRC_DIR}/lua.hpp)
        file(WRITE ${LUA_SRC_DIR}/lua.hpp "#ifndef LUA_HPP\n#define LUA_HPP\nextern \"C\" {\n#include \"lua.h\"\n#include \"lauxlib.h\"\n#include \"lualib.h\"\n}\n#endif\n")
        message(STATUS "Created lua.hpp for Lua 5.1 compatibility")
    endif()
    
    set(LUA_LIBS liblua)
    set(LUA_INC ${LUA_SRC_DIR})
    set(SOL_LUA_VER 501)
endif()

FetchContent_Declare(
    sol2
    URL "https://github.com/ThePhD/sol2/archive/refs/tags/v3.3.0.zip"
    DOWNLOAD_EXTRACT_TIMESTAMP true
)
# --- HTML/Markdown/XML Dependencies ---
# Set BRLS_DEPS_PATH to a local directory if you want to use pre-downloaded dependencies
# For example: cmake -DBRLS_DEPS_PATH=E:/deps ..
if(NOT BRLS_DEPS_PATH)
    set(BRLS_DEPS_PATH "${CMAKE_CURRENT_BINARY_DIR}/_deps_local")
endif()

# Force FetchContent to use a project-local writable cache instead of CMake's
# default `_deps` directory. This avoids permission issues in shared/container
# build roots where `${CMAKE_CURRENT_BINARY_DIR}/_deps` may already exist with
# incompatible ownership.
file(MAKE_DIRECTORY "${BRLS_DEPS_PATH}")
set(FETCHCONTENT_BASE_DIR "${BRLS_DEPS_PATH}" CACHE PATH "FetchContent base directory" FORCE)
message(STATUS "--- FetchContent base dir: ${FETCHCONTENT_BASE_DIR} ---")

FetchContent_Declare(
    pugixml
    URL https://github.com/zeux/pugixml/archive/refs/tags/v1.14.zip
    DOWNLOAD_EXTRACT_TIMESTAMP true
)

FetchContent_Declare(
    libwebp
    URL https://github.com/webmproject/libwebp/archive/refs/tags/v1.3.2.zip
    DOWNLOAD_EXTRACT_TIMESTAMP true
)

# Only build the core libwebp library, not examples/tools
set(WEBP_BUILD_ANIM_UTILS OFF CACHE BOOL "" FORCE)
set(WEBP_BUILD_CWEBP OFF CACHE BOOL "" FORCE)
set(WEBP_BUILD_DWEBP OFF CACHE BOOL "" FORCE)
set(WEBP_BUILD_GIF2WEBP OFF CACHE BOOL "" FORCE)
set(WEBP_BUILD_IMG2WEBP OFF CACHE BOOL "" FORCE)
set(WEBP_BUILD_VWEBP OFF CACHE BOOL "" FORCE)
set(WEBP_BUILD_WEBPINFO OFF CACHE BOOL "" FORCE)
set(WEBP_BUILD_WEBPMUX OFF CACHE BOOL "" FORCE)
set(WEBP_BUILD_EXTRAS OFF CACHE BOOL "" FORCE)

FetchContent_MakeAvailable(sol2 pugixml libwebp)

# Get libwebp source dir explicitly
FetchContent_GetProperties(libwebp)
if(NOT libwebp_POPULATED)
    FetchContent_Populate(libwebp)
endif()
set(WebP_INCLUDE_DIRS "${libwebp_SOURCE_DIR}/src")

# Link against borealis and Lua
# Configure Borealis options before adding it
if(PLATFORM_SWITCH OR SWITCH OR __SWITCH__ OR CMAKE_SYSTEM_NAME STREQUAL "NintendoSwitch")
    set(PLATFORM_SWITCH ON CACHE BOOL "Build for Nintendo Switch" FORCE)
    set(PLATFORM_DESKTOP OFF CACHE BOOL "Build for Desktop" FORCE)
    set(USE_SDL2 ON CACHE BOOL "Use SDL2 instead of GLFW" FORCE)
    
    set(BOREALIS_USE_DEKO3D OFF CACHE BOOL "Disable deko3d" FORCE)
    set(BOREALIS_USE_OPENGL ON CACHE BOOL "Use OpenGL" FORCE)
    
    if(WIN32 AND NOT MINGW AND NOT CYGWIN AND NOT MSYS)
        message(FATAL_ERROR "\n"
            "--------------------------------------------------------------------------\n"
            " ERROR: Detected Windows CMake while targeting Nintendo Switch.\n"
            " This will cause 'multiple target patterns' errors in Make.\n"
            " Please use the MSYS2 terminal and MSYS2 version of CMake.\n"
            "--------------------------------------------------------------------------\n")
    endif()
else()
    set(PLATFORM_DESKTOP ON CACHE BOOL "Build for Desktop" FORCE)
    set(PLATFORM_SWITCH OFF CACHE BOOL "Build for Nintendo Switch" FORCE)
endif()

set(BRLS_UNITY_BUILD ON CACHE BOOL "Enable unity build" FORCE)

# Add Borealis as a subproject AFTER all dependencies are configured
# Moved down to ensure include paths like libwebp_SOURCE_DIR are available

# Our application
if(MSVC)
    add_compile_options(/bigobj)
endif()

set(APP_SOURCES
    src/main.cpp
    src/lua_manager.cpp
    src/lua/lua_core.cpp
    src/lua/lua_view.cpp
    src/lua/lua_cells.cpp
    src/lua/lua_animation.cpp
    src/lua/lua_recycler.cpp
    src/network/http_client.cpp
    src/lua/lua_network.cpp
    src/xml_loader.cpp
    src/zip_loader.cpp
    src/html/html_renderer.cpp
    src/html/html_parser.cpp
    src/html/html_style.cpp
    src/html/html_view_builder.cpp
    src/html/markdown_renderer.cpp
    src/html/format_converters.cpp
    src/lua/lua_html.cpp
    src/lua/lua_ssh.cpp
)
add_executable(lorealis ${APP_SOURCES})

target_include_directories(lorealis PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/include")

# Sol2 v3 header path
FetchContent_GetProperties(sol2)
if(sol2_POPULATED)
    target_include_directories(lorealis PRIVATE ${sol2_SOURCE_DIR}/include)
endif()

# Link against borealis and Lua
target_include_directories(lorealis BEFORE PRIVATE ${LUA_INC})
target_link_libraries(lorealis PRIVATE borealis sol2::sol2 ${LUA_LIBS} pugixml webp)

# zlib for ZipLoader (DEFLATE decompression)
if(NOT PLATFORM_SWITCH)
    # Fetch zlib automatically (so it works on all desktop platforms)
    FetchContent_Declare(
        zlib_src
        URL "https://github.com/madler/zlib/releases/download/v1.3.1/zlib-1.3.1.tar.gz"
    )
    set(ZLIB_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
    set(SKIP_INSTALL_ALL ON CACHE BOOL "" FORCE)
    FetchContent_MakeAvailable(zlib_src)
    # FetchContent creates zlibstatic target
    target_include_directories(lorealis PRIVATE ${zlib_src_SOURCE_DIR} ${zlib_src_BINARY_DIR})
    target_link_libraries(lorealis PRIVATE zlibstatic)
    message(STATUS "--- ZipLoader: Using fetched zlib (zlibstatic) ---")
endif()

message(STATUS "--- Adding Borealis subproject ---")
set(BRLS_RESOURCES_DIR "./res")
list(APPEND BOREALIS_INCLUDE ${WebP_INCLUDE_DIRS})
add_subdirectory(lib/borealis/library)
target_include_directories(borealis PUBLIC ${WebP_INCLUDE_DIRS})
# On Switch, zlib is already linked via 'z' (see Switch section below)

# Ensure everything is linked statically
set(BUILD_SHARED_LIBS OFF CACHE BOOL "Build static libraries" FORCE)

# If on Desktop, link glfw
if(NOT PLATFORM_SWITCH AND NOT USE_SDL2)
    target_link_libraries(lorealis PRIVATE glfw)
    target_include_directories(lorealis PRIVATE lib/borealis/library/lib/extern/glfw/include)
endif()

# Fix Borealis Switch-SDL2 configuration
if(PLATFORM_SWITCH AND USE_SDL2)
    target_compile_definitions(borealis PUBLIC __SDL2__)
    target_compile_definitions(lorealis PRIVATE __SDL2__)
    
    if(EXISTS "/opt/devkitpro/portlibs/switch/include")
        target_include_directories(borealis PUBLIC "/opt/devkitpro/portlibs/switch/include")
        target_include_directories(lorealis PRIVATE "/opt/devkitpro/portlibs/switch/include")
    endif()
endif()

# POSIX Compatibility and MSVC Fixes
if(MSVC)
    set(BRLS_COMPAT_INCLUDE "${CMAKE_CURRENT_SOURCE_DIR}/include/compat")
    target_include_directories(lorealis PRIVATE ${BRLS_COMPAT_INCLUDE})
    target_include_directories(borealis PUBLIC ${BRLS_COMPAT_INCLUDE})
    
    set(MSVC_FIXES 
        BOREALIS_USE_STD_THREAD
        NOMINMAX
        _CRT_SECURE_NO_WARNINGS
        _CRT_NONSTDC_NO_DEPRECATE
        _SILENCE_CXX17_CODECVT_HEADER_DEPRECATION_WARNING
        _SILENCE_ALL_CXX17_DEPRECATION_WARNINGS
    )
    
    target_compile_definitions(lorealis PRIVATE ${MSVC_FIXES})
    target_compile_definitions(borealis PUBLIC ${MSVC_FIXES})
    set_target_properties(borealis PROPERTIES CXX_STANDARD 20)
    target_link_libraries(lorealis PRIVATE winmm shell32 wininet)

    add_compile_options(/MP)
    message(STATUS "--- Build Optimization: Multi-process compilation (/MP) ENABLED ---")
endif()

# ── libssh2 Integration ──────────────────────────────────────
# On Switch (devkitPro): pkg_check_modules(LIBSSH2 REQUIRED libssh2)
# On Desktop: FetchContent or system install
if(PLATFORM_SWITCH)
    pkg_check_modules(LIBSSH2 REQUIRED libssh2)
    target_include_directories(lorealis PRIVATE ${LIBSSH2_INCLUDE_DIRS})
    target_link_libraries(lorealis PRIVATE ${LIBSSH2_LIBRARIES})
    message(STATUS "--- SSH: Using devkitPro libssh2 ---")
else()
    # Try system libssh2 first
    find_package(PkgConfig QUIET)
    if(PkgConfig_FOUND)
        pkg_check_modules(LIBSSH2 QUIET libssh2)
    endif()
    if(LIBSSH2_FOUND)
        target_include_directories(lorealis PRIVATE ${LIBSSH2_INCLUDE_DIRS})
        target_link_libraries(lorealis PRIVATE ${LIBSSH2_LIBRARIES})
        message(STATUS "--- SSH: Using system libssh2 (${LIBSSH2_VERSION}) ---")
    else()
        # 获取并构建 mbedTLS（CMake 原生支持，比 OpenSSL 更易构建）
        message(STATUS "--- SSH: Fetching and building mbedTLS ---")
        set(MBEDTLS_FETCH_DIR "${FETCHCONTENT_BASE_DIR}/mbedtls_v2_28_4")
        FetchContent_Declare(
            mbedtls_src
            GIT_REPOSITORY "https://github.com/Mbed-TLS/mbedtls.git"
            GIT_TAG "v2.28.4"  # LTS 版本，稳定兼容
            GIT_SHALLOW TRUE
            GIT_PROGRESS TRUE
            UPDATE_DISCONNECTED TRUE
            SOURCE_DIR "${MBEDTLS_FETCH_DIR}/src"
            BINARY_DIR "${MBEDTLS_FETCH_DIR}/build"
            SUBBUILD_DIR "${MBEDTLS_FETCH_DIR}/subbuild"
        )
        # 为 mbedTLS 设置兼容性策略（它使用旧版 CMake 语法）
        set(CMAKE_POLICY_VERSION_MINIMUM 3.5)
        # mbedTLS 选项
        set(ENABLE_TESTING OFF CACHE BOOL "" FORCE)
        set(ENABLE_PROGRAMS OFF CACHE BOOL "" FORCE)
        set(USE_SHARED_MBEDTLS_LIBRARY OFF CACHE BOOL "" FORCE)
        FetchContent_MakeAvailable(mbedtls_src)
        # 恢复策略设置
        unset(CMAKE_POLICY_VERSION_MINIMUM)
        
        # 设置 mbedTLS 路径供 libssh2 使用
        # FetchContent 使用 <name>_BINARY_DIR 和 <name>_SOURCE_DIR 格式
        set(MBEDCRYPTO_LIBRARY ${mbedtls_src_BINARY_DIR}/library/${CMAKE_STATIC_LIBRARY_PREFIX}mbedcrypto${CMAKE_STATIC_LIBRARY_SUFFIX})
        set(MBEDX509_LIBRARY ${mbedtls_src_BINARY_DIR}/library/${CMAKE_STATIC_LIBRARY_PREFIX}mbedx509${CMAKE_STATIC_LIBRARY_SUFFIX})
        set(MBEDTLS_LIBRARY ${mbedtls_src_BINARY_DIR}/library/${CMAKE_STATIC_LIBRARY_PREFIX}mbedtls${CMAKE_STATIC_LIBRARY_SUFFIX})
        set(MBEDTLS_INCLUDE_DIR ${mbedtls_src_SOURCE_DIR}/include)
        message(STATUS "--- mbedTLS source: ${mbedtls_src_SOURCE_DIR} ---")
        message(STATUS "--- mbedTLS binary: ${mbedtls_src_BINARY_DIR} ---")
        message(STATUS "--- mbedTLS library: ${MBEDTLS_LIBRARY} ---")

        # Fallback: fetch and build libssh2 from source
        FetchContent_Declare(
            libssh2_src
            URL "https://github.com/libssh2/libssh2/releases/download/libssh2-1.11.0/libssh2-1.11.0.tar.gz"
            DOWNLOAD_EXTRACT_TIMESTAMP true
        )
        # 设置兼容策略以支持旧版 CMakeLists.txt
        set(CMAKE_POLICY_VERSION_MINIMUM 3.10)
        # libssh2 选项
        set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
        set(BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
        set(BUILD_TESTING  OFF CACHE BOOL "" FORCE)
        # 禁用 pkgconfig 生成
        set(LIBSSH2_ENABLE_PKGCONFIG OFF CACHE BOOL "" FORCE)
        # 强制使用 mbedTLS 后端（比 WinCNG 兼容性好）
        set(CRYPTO_BACKEND "mbedTLS" CACHE STRING "Crypto backend for libssh2" FORCE)
        # 在 FetchContent_MakeAvailable 之前创建缺失的 libssh2.pc.in 文件
        # 这样可以避免 configure_file 错误
        FetchContent_GetProperties(libssh2_src)
        if(NOT libssh2_src_POPULATED)
            FetchContent_Populate(libssh2_src)
        endif()
        # libssh2 的 src/CMakeLists.txt:188 错误地使用 ${CMAKE_SOURCE_DIR} 查找 libssh2.pc.in
        # 需要在主项目根目录创建 workaround 文件
        if(NOT EXISTS "${CMAKE_SOURCE_DIR}/libssh2.pc.in")
            file(WRITE "${CMAKE_SOURCE_DIR}/libssh2.pc.in" "prefix=@CMAKE_INSTALL_PREFIX@
exec_prefix=@CMAKE_INSTALL_PREFIX@
libdir=@CMAKE_INSTALL_FULL_LIBDIR@
includedir=@CMAKE_INSTALL_FULL_INCLUDEDIR@

Name: libssh2
Description: The SSH library
Version: @LIBSSH2_VERSION@
Libs: -L${libdir} -lssh2
Libs.private: @LIBSSH2_PC_LIBS_PRIVATE@
Cflags: -I${includedir}
")
        endif()
        # 同时也在 libssh2 源码目录创建
        if(NOT EXISTS "${libssh2_src_SOURCE_DIR}/libssh2.pc.in")
            file(WRITE "${libssh2_src_SOURCE_DIR}/libssh2.pc.in" "prefix=@CMAKE_INSTALL_PREFIX@
exec_prefix=@CMAKE_INSTALL_PREFIX@
libdir=@CMAKE_INSTALL_FULL_LIBDIR@
includedir=@CMAKE_INSTALL_FULL_INCLUDEDIR@

Name: libssh2
Description: The SSH library
Version: @LIBSSH2_VERSION@
Libs: -L${libdir} -lssh2
Libs.private: @LIBSSH2_PC_LIBS_PRIVATE@
Cflags: -I${includedir}
")
        endif()
        if(NOT EXISTS "${libssh2_src_SOURCE_DIR}/src/libssh2.pc.in")
            file(WRITE "${libssh2_src_SOURCE_DIR}/src/libssh2.pc.in" "prefix=@CMAKE_INSTALL_PREFIX@
exec_prefix=@CMAKE_INSTALL_PREFIX@
libdir=@CMAKE_INSTALL_FULL_LIBDIR@
includedir=@CMAKE_INSTALL_FULL_INCLUDEDIR@

Name: libssh2
Description: The SSH library
Version: @LIBSSH2_VERSION@
Libs: -L${libdir} -lssh2
Libs.private: @LIBSSH2_PC_LIBS_PRIVATE@
Cflags: -I${includedir}
")
        endif()
        add_subdirectory(${libssh2_src_SOURCE_DIR} ${libssh2_src_BINARY_DIR})
        unset(CMAKE_POLICY_VERSION_MINIMUM)
        target_include_directories(lorealis PRIVATE ${libssh2_src_SOURCE_DIR}/include)
        
        # 链接 mbedTLS 库到主项目（libssh2 在内部应该已链接，但主项目也需要）
        if(NOT TARGET mbedtls)
            message(FATAL_ERROR "mbedTLS target not found!")
        endif()
        
        if(WIN32)
            target_link_libraries(lorealis PRIVATE libssh2_static mbedtls mbedx509 mbedcrypto ws2_32 crypt32)
        else()
            target_link_libraries(lorealis PRIVATE libssh2_static mbedtls mbedx509 mbedcrypto)
        endif()
        message(STATUS "--- SSH: Using fetched libssh2 (${CRYPTO_BACKEND}) ---")
        message(STATUS "--- mbedTLS libs: mbedtls mbedx509 mbedcrypto ---")
    endif()
    # On Windows also need winsock2
    if(WIN32)
        target_link_libraries(lorealis PRIVATE ws2_32)
    endif()
endif()

# Switch Specific Configuration
if(PLATFORM_SWITCH)
    message(STATUS "--- Switch Config Detected ---")
    target_compile_definitions(lorealis PRIVATE BRLS_RESOURCES="romfs:/")
    target_compile_definitions(lorealis PRIVATE PLATFORM_SWITCH=1)
    
    # Add libcurl and libwebp for Switch
    find_package(PkgConfig REQUIRED)
    pkg_check_modules(CURL REQUIRED libcurl)
    pkg_check_modules(WEBP REQUIRED libwebp)
    target_link_libraries(lorealis PRIVATE ${CURL_LIBRARIES} ${WEBP_LIBRARIES} z)
    target_include_directories(lorealis PRIVATE ${CURL_INCLUDE_DIRS} ${WEBP_INCLUDE_DIRS})

    set_target_properties(lorealis PROPERTIES SUFFIX ".elf")
    target_compile_definitions(lorealis PRIVATE SOL_LUA_VERSION=501)
    target_compile_definitions(lorealis PRIVATE SOL_ALL_SAFETIES_ON=1)
    target_compile_definitions(lorealis PRIVATE SOL_NO_CHECK_NUMBER_PRECISION=1)
    
    target_compile_options(lorealis PRIVATE -Wno-error=template-body)

    if(WIN32)
        set(SWITCH_REPACK_ROMFS_COMMAND
            powershell.exe -ExecutionPolicy Bypass -File "${CMAKE_SOURCE_DIR}/scripts/repack_switch_romfs.ps1" -BuildDir "${CMAKE_BINARY_DIR}")
    else()
        set(SWITCH_REPACK_ROMFS_COMMAND
            /bin/bash "${CMAKE_SOURCE_DIR}/scripts/repack_switch_romfs.sh" "${CMAKE_BINARY_DIR}")
    endif()

    add_custom_target(switch_repack_romfs
        COMMAND ${CMAKE_COMMAND} -E echo "Repacking romfs into existing Lorealis.nro"
        COMMAND ${SWITCH_REPACK_ROMFS_COMMAND}
        DEPENDS lorealis
        WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
        COMMENT "Repack Switch romfs without rebuilding code"
        VERBATIM)
else()
    target_compile_definitions(lorealis PRIVATE SOL_LUA_VERSION=501)
    target_compile_definitions(lorealis PRIVATE SOL_ALL_SAFETIES_ON=1)

    message(STATUS "--- Desktop/Win32 Config Detected ---")
    target_compile_definitions(lorealis PRIVATE BRLS_RESOURCES="./res/")
endif()

# FFmpeg & MPV Integration (Currently Disabled)
# if(PLATFORM_SWITCH)
#     find_package(PkgConfig REQUIRED)
#     pkg_check_modules(MPV REQUIRED mpv)
#     target_compile_definitions(lorealis PRIVATE ENABLE_INTERNAL_PLAYER=1)
#     target_link_libraries(lorealis PRIVATE ${MPV_LIBRARIES})
# else()
#     set(MPV_FOUND_ANY FALSE)
#     if(MPV_FOUND_ANY)
#         target_compile_definitions(lorealis PRIVATE ENABLE_INTERNAL_PLAYER=1)
#     endif()
#     if(WIN32)
#         target_link_libraries(lorealis PRIVATE winmm shell32)
#     endif()
# endif()
