#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Android build driver for Silent Hill DS+.
#
#   android/build.sh check            verify the host toolchain
#   android/build.sh fetch            clone pinned sources, apply the patch
#   android/build.sh deps             build SDL2 / OpenAL Soft / libjpeg with the NDK
#   android/build.sh game             build libmain.so (the patched upstream pc_port)
#   android/build.sh stage            stage libs, SDL Java sources and APK assets
#   android/build.sh apk              assemble the debug APK with Gradle
#   android/build.sh all              all of the above (default)
#
# The RG DS Plus build (tools/build.sh + patches/*-rgds.patch) is untouched:
# this is a separate, single-screen native port built from the same pinned
# upstream commit. See android/README.md.

set -eu

HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/.." && pwd)
. "$HERE/versions.env"

WORK=${SH_ANDROID_WORK:-"$ROOT/.android-work"}
UPSTREAM="$WORK/upstream"
THIRD="$WORK/third_party"
MODE=${1:-all}

die()  { echo "android/build.sh: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "missing tool: $1"; }
log()  { printf '\n=== %s ===\n' "$*"; }

ANDROID_SDK_ROOT=${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}
[ -n "$ANDROID_SDK_ROOT" ] || die "set ANDROID_SDK_ROOT (or ANDROID_HOME) to your Android SDK"
NDK=${ANDROID_NDK_HOME:-"$ANDROID_SDK_ROOT/ndk/$ANDROID_NDK_VERSION"}
TOOLCHAIN="$NDK/build/cmake/android.toolchain.cmake"
JOBS=${JOBS:-$(python3 -c 'import os; print(os.cpu_count() or 4)')}
PYTHON=$(command -v python3)

case "$(uname -s)" in
    Darwin) HOST_TAG=darwin-x86_64 ;;
    Linux)  HOST_TAG=linux-x86_64 ;;
    *)      die "unsupported host OS (need an NDK prebuilt for it)" ;;
esac
LLVM_NM="$NDK/toolchains/llvm/prebuilt/$HOST_TAG/bin/llvm-nm"
LLVM_OBJCOPY="$NDK/toolchains/llvm/prebuilt/$HOST_TAG/bin/llvm-objcopy"
LLVM_STRIP="$NDK/toolchains/llvm/prebuilt/$HOST_TAG/bin/llvm-strip"

# Needed by SH_STATIC_MAPS (pc_port/tools/prefix_map_syms.py) and by
# gen_build_info.cmake; host tools must not be looked up in the target sysroot.
ROOT_PATH_ARGS='-DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY -DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=ONLY'

# The decomp is a WIP and relies on implicit declarations / int-to-pointer
# conversions. NDK Clang turns several of those into errors by default.
# format-security is in here as well: the engine logs values it builds at
# runtime, and NDK's -Werror=format-security rejects passing those as formats.
WARN_ARGS='-Wno-unknown-warning-option -Wno-error=format-security -Wno-format-security -Wno-error=return-type -Wno-error=implicit-function-declaration -Wno-error=implicit-int -Wno-error=int-conversion -Wno-error=incompatible-pointer-types -Wno-error=return-mismatch -Wno-error=declaration-missing-parameter-type'

check_host() {
    need git
    need cmake
    need ninja
    need python3
    need curl
    [ -f "$TOOLCHAIN" ] || die "NDK $ANDROID_NDK_VERSION not found at $NDK (install it with sdkmanager)"
    [ -x "$LLVM_NM" ] || die "missing $LLVM_NM (SH_STATIC_MAPS needs llvm-nm)"
    [ -x "$LLVM_OBJCOPY" ] || die "missing $LLVM_OBJCOPY (SH_STATIC_MAPS needs llvm-objcopy)"
    [ -x "$LLVM_STRIP" ] || die "missing $LLVM_STRIP"
    [ -d "$ANDROID_SDK_ROOT/platforms/android-$ANDROID_COMPILE_SDK" ] || \
        die "missing Android platform $ANDROID_COMPILE_SDK in $ANDROID_SDK_ROOT"
    echo "SDK:      $ANDROID_SDK_ROOT"
    echo "NDK:      $NDK"
    echo "ABIs:     $ANDROID_ABIS"
    echo "Work dir: $WORK"
}

clone_pinned() {
    _url=$1; _ref=$2; _dir=$3
    if [ ! -d "$_dir/.git" ]; then
        mkdir -p "$(dirname "$_dir")"
        log "cloning $_url at $_ref"
        # Only one pinned tree is ever built, so a single-commit clone is
        # enough. Full-history clones of these repositories are hundreds of
        # megabytes and regularly die halfway over a slow or proxied link
        # ("early EOF" / "unexpected disconnect"), which then costs a restart.
        if ! GIT_TERMINAL_PROMPT=0 git clone --quiet --depth 1 --no-tags \
                --branch "$_ref" "$_url" "$_dir"; then
            # _ref is a raw commit: it cannot be cloned by name, so fetch just
            # that commit instead.
            rm -rf "$_dir"
            git init --quiet "$_dir"
            git -C "$_dir" remote add origin "$_url"
            GIT_TERMINAL_PROMPT=0 git -C "$_dir" fetch --quiet --depth 1 \
                origin "$_ref" || die "cannot fetch $_ref from $_url"
            git -C "$_dir" checkout --quiet FETCH_HEAD
        fi
    fi
    git -C "$_dir" checkout --quiet "$_ref" || \
        die "$_dir does not contain $_ref"
}

fetch_sources() {
    log "fetching pinned sources"
    clone_pinned "$UPSTREAM_REPO" "$UPSTREAM_COMMIT" "$UPSTREAM"
    clone_pinned "$SDL2_REPO"     "$SDL2_REF"       "$THIRD/SDL"
    clone_pinned "$OPENAL_REPO"   "$OPENAL_REF"     "$THIRD/openal-soft"
    clone_pinned "$JPEG_REPO"     "$JPEG_REF"       "$THIRD/libjpeg-turbo"

    if ! git -C "$UPSTREAM" submodule update --init --depth 1 pc_port/PsyCross; then
        git -C "$UPSTREAM" submodule update --init pc_port/PsyCross
    fi
    _psycross=$(git -C "$UPSTREAM/pc_port/PsyCross" rev-parse HEAD)
    [ "$_psycross" = "$PSYCROSS_COMMIT" ] || \
        die "PsyCross submodule is at $_psycross, expected $PSYCROSS_COMMIT"

    # PsyCross advertises an Android/GLES3 path, but its __ANDROID__ branch is
    # incomplete: it defines eprintinfof/eprintwarnf while the whole engine
    # calls eprintinfo/eprintwarn, and it feeds runtime strings to
    # __android_log_print(). Nothing under __ANDROID__ had ever been compiled,
    # so this patch is a fix, not an adaptation. It is applied inside the
    # submodule, which is why it cannot live in the upstream tree patch.
    _psycross_stamp="$UPSTREAM/pc_port/PsyCross/.sh-android-patched"
    if [ ! -f "$_psycross_stamp" ]; then
        git -C "$UPSTREAM/pc_port/PsyCross" apply "$HERE/patches/psycross-android.patch" || \
            die "PsyCross patch failed to apply (is PSYCROSS_COMMIT still $PSYCROSS_COMMIT?)"
        touch "$_psycross_stamp"
    fi

    # The RG DS Plus patch is deliberately NOT applied: it is a two-process,
    # two-window Wayland port for the RG DS hardware. Android uses the upstream
    # single-screen code with only the small Android adaptation patch.
    _stamp="$UPSTREAM/.sh-android-patched"
    if [ ! -f "$_stamp" ]; then
        cp "$HERE/native/sh_android.c" "$UPSTREAM/pc_port/src/sh_android.c"
        cp "$HERE/native/sh_android.h" "$UPSTREAM/pc_port/include/sh_android.h"
        git -C "$UPSTREAM" apply "$HERE/patches/silent-hill-android.patch" || \
            die "android patch failed to apply (is UPSTREAM_COMMIT still $UPSTREAM_COMMIT?)"
        touch "$_stamp"
    fi
}

ndk_cmake() {
    # shellcheck disable=SC2086
    cmake -G Ninja \
        -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN" \
        -DANDROID_ABI="$ABI" \
        -DANDROID_PLATFORM="$ANDROID_PLATFORM" \
        -DANDROID_STL="$ANDROID_STL" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_DISABLE_FIND_PACKAGE_PkgConfig=TRUE \
        $ROOT_PATH_ARGS \
        "$@"
}

build_deps() {
    mkdir -p "$WORK/deps-build"
    for dep in SDL openal-soft libjpeg-turbo; do
        src="$THIRD/$dep"
        [ -f "$src/CMakeLists.txt" ] || die "$src is missing; run: android/build.sh fetch"
    done

    log "building SDL2 $SDL2_REF"
    ndk_cmake -S "$THIRD/SDL" -B "$WORK/deps-build/$ABI/SDL" \
        -DCMAKE_INSTALL_PREFIX="$DEPS" \
        -DCMAKE_SHARED_LINKER_FLAGS="-Wl,-soname,libSDL2.so" \
        -DSDL_SHARED=ON -DSDL_STATIC=OFF -DSDL_TEST=OFF -DSDL_TESTS=OFF \
        -DSDL2_DISABLE_SDL2MAIN=ON -DSDL2_DISABLE_INSTALL=OFF
    cmake --build "$WORK/deps-build/$ABI/SDL" -j "$JOBS"
    cmake --install "$WORK/deps-build/$ABI/SDL"

    log "building OpenAL Soft $OPENAL_REF"
    ndk_cmake -S "$THIRD/openal-soft" -B "$WORK/deps-build/$ABI/openal" \
        -DCMAKE_INSTALL_PREFIX="$DEPS" \
        -DCMAKE_SHARED_LINKER_FLAGS="-Wl,-soname,libopenal.so" \
        -DLIBTYPE=SHARED -DALSOFT_ENABLE_MODULES=OFF \
        -DALSOFT_UTILS=OFF -DALSOFT_EXAMPLES=OFF -DALSOFT_TESTS=OFF \
        -DALSOFT_INSTALL_CONFIG=OFF -DALSOFT_INSTALL_HRTF_DATA=OFF \
        -DALSOFT_INSTALL_AMBDEC_PRESETS=OFF -DALSOFT_INSTALL_EXAMPLES=OFF \
        -DALSOFT_INSTALL_UTILS=OFF -DALSOFT_UPDATE_BUILD_VERSION=OFF \
        -DALSOFT_BACKEND_PIPEWIRE=OFF -DALSOFT_BACKEND_PULSEAUDIO=OFF \
        -DALSOFT_BACKEND_ALSA=OFF -DALSOFT_BACKEND_OSS=OFF \
        -DALSOFT_BACKEND_JACK=OFF -DALSOFT_BACKEND_SNDIO=OFF \
        -DALSOFT_BACKEND_OBOE=OFF -DALSOFT_BACKEND_OPENSL=ON
    cmake --build "$WORK/deps-build/$ABI/openal" -j "$JOBS"
    cmake --install "$WORK/deps-build/$ABI/openal"

    log "building libjpeg-turbo $JPEG_REF (static)"
    ndk_cmake -S "$THIRD/libjpeg-turbo" -B "$WORK/deps-build/$ABI/jpeg" \
        -DCMAKE_INSTALL_PREFIX="$DEPS" -DCMAKE_INSTALL_LIBDIR=lib \
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
        -DENABLE_SHARED=OFF -DENABLE_STATIC=ON -DWITH_SIMD=OFF \
        -DWITH_TURBOJPEG=OFF
    cmake --build "$WORK/deps-build/$ABI/jpeg" -j "$JOBS"
    cmake --install "$WORK/deps-build/$ABI/jpeg"

    for f in libSDL2.so libopenal.so libjpeg.a; do
        [ -f "$DEPS/lib/$f" ] || die "dependency build did not produce $DEPS/lib/$f"
    done
}

build_game() {
    log "building libmain.so for $ABI"
    [ -f "$UPSTREAM/.sh-android-patched" ] || die "run: android/build.sh fetch"
    # shellcheck disable=SC2086
    ndk_cmake -S "$UPSTREAM/pc_port" -B "$BUILD" \
        -DCMAKE_MODULE_PATH="$HERE/cmake" \
        -DSH_ANDROID_DEPS_PREFIX="$DEPS" \
        -DCMAKE_C_FLAGS="$WARN_ARGS" \
        -DCMAKE_CXX_FLAGS="$WARN_ARGS" \
        -DJPEG_LIBRARY="$DEPS/lib/libjpeg.a" \
        -DJPEG_INCLUDE_DIR="$DEPS/include" \
        -DSH_STATIC_MAPS=ON -DSH_BUILD_MAP_DLLS=OFF \
        -DSH_ENABLE_RETROACHIEVEMENTS=OFF -DSH_FMV_FFMPEG=OFF -DSH_DEBUG=OFF \
        -DSH_VERSION=USA -DBUILD_TESTING=OFF \
        -DPython3_EXECUTABLE="$PYTHON" \
        -DSH_LLVM_NM="$LLVM_NM" -DSH_LLVM_OBJCOPY="$LLVM_OBJCOPY"
    cmake --build "$BUILD" --target SilentHillPC -j "$JOBS"
    [ -f "$BUILD/libmain.so" ] || die "build did not produce $BUILD/libmain.so"
}

stage_apk_inputs() {
    log "staging Gradle inputs for $ABI"
    # AGP strips .so files it builds itself; it does not touch prebuilt jniLibs,
    # and these are assembled by hand. Unstripped they were 33 MB (libmain) and
    # 36 MB (libopenal) of debug sections, which is most of a 39 MB APK. Local
    # symbols are not needed at runtime: the static map overlays are resolved by
    # the linker, and SDLActivity looks SDL_main up in .dynsym, which
    # --strip-unneeded keeps. Set SH_KEEP_SYMBOLS=1 to keep them for debugging.
    if [ "${SH_KEEP_SYMBOLS:-0}" != "1" ]; then
        log "stripping debug symbols for $ABI"
        for so in "$BUILD/libmain.so" "$DEPS/lib/libSDL2.so" "$DEPS/lib/libopenal.so"; do
            [ -f "$so" ] || die "missing $so"
            "$LLVM_STRIP" --strip-unneeded "$so"
        done
    fi
    python3 "$HERE/tools/stage.py" \
        --root "$ROOT" --work "$WORK" --abi "$ABI" \
        --deps "$DEPS" --build "$BUILD" --ndk "$NDK"
}

assemble_apk() {
    log "assembling debug APK"
    GRADLE=${GRADLE_BIN:-gradle}
    need "$GRADLE"
    # Gradle's package task overwrites app-debug.apk in place, and when the new
    # APK is smaller than the previous one the tail of the old file survives.
    # Stripping makes that the normal case (26 MB -> 5.8 MB), and the leftover
    # bytes are unreachable but real: one rebuild produced a 26 MB APK holding
    # 14 MB of entries. Remove the target so each package starts from nothing.
    rm -f "$HERE/app/build/outputs/apk/debug/app-debug.apk"
    (cd "$HERE" && "$GRADLE" --no-daemon :app:assembleDebug)
    apk="$HERE/app/build/outputs/apk/debug/app-debug.apk"
    [ -f "$apk" ] || die "Gradle did not produce $apk"
    mkdir -p "$ROOT/dist"
    out="$ROOT/dist/SilentHill-Android-debug.apk"
    cp "$apk" "$out"
    echo "APK: $out"
}

for_each_abi() {
    _action=$1
    for ABI in $ANDROID_ABIS; do
        DEPS="$WORK/deps/$ABI"
        BUILD="$WORK/build/$ABI"
        "$_action"
    done
}

case "$MODE" in
    check) check_host ;;
    fetch) check_host; fetch_sources ;;
    deps)  check_host; fetch_sources; for_each_abi build_deps ;;
    game)  check_host; for_each_abi build_game ;;
    stage) for_each_abi stage_apk_inputs ;;
    apk)   check_host; for_each_abi stage_apk_inputs; assemble_apk ;;
    all)   check_host; fetch_sources; for_each_abi build_deps; for_each_abi build_game;
           for_each_abi stage_apk_inputs; assemble_apk ;;
    *)     die "unknown command '$MODE' (check|fetch|deps|game|stage|apk|all)" ;;
esac
