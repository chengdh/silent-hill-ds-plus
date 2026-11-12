# SPDX-License-Identifier: GPL-3.0-or-later
# Minimal OpenAL find module for the Android cross-build.
#
# PsyCross link-checks AL symbols and the PC port's xa_player.c includes
# <AL/al.h> directly, so both an imported target and OPENAL_INCLUDE_DIR are
# needed. The library is OpenAL Soft built from source with the NDK; see
# android/build.sh. It stays a shared library to honour the LGPL.

if(NOT SH_ANDROID_DEPS_PREFIX)
    message(FATAL_ERROR "SH_ANDROID_DEPS_PREFIX must point at the per-ABI dependency prefix")
endif()

set(_sh_prefix "${SH_ANDROID_DEPS_PREFIX}")
set(_sh_openal "${_sh_prefix}/lib/libopenal.so")

if(NOT EXISTS "${_sh_openal}")
    message(FATAL_ERROR "OpenAL Soft not built for this ABI: missing ${_sh_openal}. Run android/build.sh deps first.")
endif()

set(OPENAL_LIBRARY "${_sh_openal}")
set(OPENAL_INCLUDE_DIR "${_sh_prefix}/include")
set(OpenAL_FOUND TRUE)

if(NOT TARGET OpenAL::OpenAL)
    add_library(OpenAL::OpenAL SHARED IMPORTED GLOBAL)
    set_target_properties(OpenAL::OpenAL PROPERTIES
        IMPORTED_LOCATION "${_sh_openal}"
        INTERFACE_INCLUDE_DIRECTORIES "${OPENAL_INCLUDE_DIR}")
endif()

unset(_sh_prefix)
unset(_sh_openal)
