# SPDX-License-Identifier: GPL-3.0-or-later
# Minimal SDL2 find module for the Android cross-build.
#
# pc_port/CMakeLists.txt and PsyCross/CMakeLists.txt both call
# find_package(SDL2). A host pkg-config / SDL2Config.cmake must never win in a
# cross-compile, so android/build.sh puts this directory on CMAKE_MODULE_PATH
# and points SH_ANDROID_DEPS_PREFIX at the per-ABI install prefix it built.
#
# CMake's Android platform sets CMAKE_PLATFORM_NO_VERSIONED_SONAME, and the
# dependency is built with an explicit -soname, so DT_NEEDED is exactly
# "libSDL2.so" and the app can load it with System.loadLibrary("SDL2").

if(NOT SH_ANDROID_DEPS_PREFIX)
    message(FATAL_ERROR "SH_ANDROID_DEPS_PREFIX must point at the per-ABI dependency prefix")
endif()

set(_sh_prefix "${SH_ANDROID_DEPS_PREFIX}")
set(_sh_sdl2 "${_sh_prefix}/lib/libSDL2.so")

if(NOT EXISTS "${_sh_sdl2}")
    message(FATAL_ERROR "SDL2 not built for this ABI: missing ${_sh_sdl2}. Run android/build.sh deps first.")
endif()

# Both spellings occur upstream: <SDL2/SDL.h> in the PC port and <SDL.h> in
# PsyCross's platform.h.
set(SDL2_INCLUDE_DIRS "${_sh_prefix}/include" "${_sh_prefix}/include/SDL2")
set(SDL2_LIBRARIES SDL2::SDL2)
set(SDL2_FOUND TRUE)
set(SDL2_VERSION "2.32.10")

if(NOT TARGET SDL2::SDL2)
    add_library(SDL2::SDL2 SHARED IMPORTED GLOBAL)
    set_target_properties(SDL2::SDL2 PROPERTIES
        IMPORTED_LOCATION "${_sh_sdl2}"
        INTERFACE_INCLUDE_DIRECTORIES "${SDL2_INCLUDE_DIRS}")
endif()

unset(_sh_prefix)
unset(_sh_sdl2)
