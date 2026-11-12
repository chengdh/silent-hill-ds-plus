# Android build support (experimental)

> 快速开始：这是给本仓库新增的 **Android 原生构建链**，与原 RG DS Plus 的 Wayland 双屏构建完全独立、互不影响。
> 需要 Android SDK / NDK 27、JDK 17、Gradle 8.7+、CMake、Ninja、Python 3。
> 最省事的方式：`docker build -t sh-android-builder -f android/Dockerfile android`，
> 然后 `docker run --rm -v "$PWD":/work -w /work/silent-hill sh-android-builder sh android/build.sh all`。
> 产物在 `dist/SilentHill-Android-debug.apk`。**APK 不含任何游戏数据**，需要你自己准备 Silent Hill 光盘镜像。
>
> 该链路已在 Docker 中从零跑通并产出 APK（详见 [Verified build](#verified-build)）；尚未在真机/模拟器上运行过。

---

## What this is

The RG DS Plus port runs as **two processes on two Wayland outputs**. That is
specific to the Anbernic RG DS Plus and ROCKNIXDS; its patches
(`patches/silent-hill-rgds.patch`, `patches/psycross-rgds.patch`) add a Wayland
surface, an inter-process bridge and a second SDL window. None of that belongs
on Android.

So this branch adds a **second, independent build** of the *same pinned
upstream commit* (`patches/manifest.json`), targeting a single screen:

```
upstream silent-hill-decomp @ 60ed020… (pc-port)
  + PsyCross submodule @ 20a2fb4…
  + patches/silent-hill-android.patch   (10 files, shared-lib target + GLES + portability fixes)
  + patches/psycross-android.patch      (4 files, GLES/Android fixes inside the submodule)
  + native/sh_android.{c,h}             (startup shim)
        |
        v  NDK CMake toolchain -> libmain.so  (SDL_main entry point)
        |
        v  SDL2 Activity (org.libsdl.app) + OpenAL Soft + static libjpeg
        |
        v  Gradle -> app-debug.apk
```

Upstream PsyCross *advertises* an `__ANDROID__` / `RENDERER_OGLES` /
`OGLES_VERSION=3` path, but that branch had never been compiled: it defines
`eprintinfof`/`eprintwarnf` while the engine calls `eprintinfo`/`eprintwarn`,
it feeds runtime strings to `__android_log_print()`, and it uses `__rdtsc()`
and desktop-only GL tokens. `patches/psycross-android.patch` fixes exactly
those; the actual renderer port is upstream's.

The original `tools/build.sh`, `tools/package.py` and both `*-rgds.patch`
files are **not modified**. Both builds can coexist in the same checkout.

## Prerequisites

| Tool | Version |
| --- | --- |
| Android SDK | platform android-34, build-tools 34.0.0, platform-tools |
| Android NDK | `27.2.12479018` |
| JDK | 17 |
| Gradle | 8.7+ (8.11.1 tested, 8.9 in the Dockerfile default) |
| CMake / Ninja / Python 3 / git | recent (CMake 4.x also works) |

Set `ANDROID_SDK_ROOT` (or `ANDROID_HOME`); `ANDROID_NDK_HOME` is optional and
defaults to `$ANDROID_SDK_ROOT/ndk/<version>`. `GRADLE_BIN` overrides the
`gradle` command, `JOBS` the parallelism, `SH_ANDROID_WORK` the work directory.

```sh
sh android/build.sh check     # verify SDK/NDK/LLVM tools before downloading anything
sh android/build.sh all       # fetch -> deps -> game -> stage -> APK
```

Individual steps: `fetch`, `deps`, `game`, `stage`, `apk`. All sources are
pinned in `versions.env`; fetched sources and build trees live under
`.android-work/` (git-ignored). Re-running a step is safe.

The supplied `Dockerfile` installs the SDK, NDK, JDK and Gradle; it only needs
network access for the SDK download, the git clones and the Android Gradle
Plugin on the first Gradle run. `--build-arg BASE_IMAGE=<image>` swaps the base
image: any image carrying JDK 17 works, which is handy when an SDK/NDK is
already baked into another image.

### Container gotchas (these cost real time)

* **The Linux NDK is x86_64-only.** On an Apple Silicon host, a native
  `linux/arm64` container cannot run NDK clang at all (`rosetta error: failed
  to open elf at /lib64/ld-linux-x86-64.so.2`). Run the amd64 variant:
  `docker run --platform linux/amd64 …`. On x86_64 hosts nothing changes.
* **A pre-baked `init.gradle` breaks Gradle.** Some Android images ship
  `/opt/gradle-home/init.gradle` that injects a `maven` repository, which
  `settings.gradle`'s `FAIL_ON_PROJECT_REPOS` policy rejects. Point Gradle
  elsewhere: `GRADLE_USER_HOME=/tmp/gh sh android/build.sh apk`.
* **Slow or proxied GitHub.** `fetch` uses single-commit shallow clones, but a
  blocked link still stalls. Rewrite the URL instead of touching the scripts:
  `git config --global url."https://<proxy>/https://github.com/".insteadOf "https://github.com/"`.

## Verified build

`sh android/build.sh all` was executed end to end in `docker` (Ubuntu 26.04,
JDK 17.0.19, Gradle 8.11.1, NDK 27.2.12479018, platform 34, CMake 4.2.3) from a
clean source tree — patches applied, dependencies compiled, APK assembled:

| Artifact | Result |
| --- | --- |
| `libmain.so` | 33 MB, AArch64 `DYN`, `SONAME=libmain.so` |
| `NEEDED` | `libSDL2.so`, `libopenal.so`, `libc++_shared.so`, `libGLESv3.so`, `libEGL.so`, `liblog.so`, `libm/libdl/libc` |
| Exported entry | `SDL_main` (`T`, found by `SDLActivity`'s `dlsym`) |
| Static map overlays | 43 map targets linked into `libmain.so` |
| `dist/SilentHill-Android-debug.apk` | 26 MB, `arm64-v8a`, minSdk 24, targetSdk 34 |
| APK payload | `lib/arm64-v8a/{libmain,libSDL2,libopenal,libc++_shared}.so`, fonts, `gamecontrollerdb.txt`, `config.cfg`, licence texts — **no game data** |

Both patches were also verified with `git apply --cached --check` against the
pristine pinned commits. What has **not** happened is a launch on a device or
emulator, so expect runtime (driver, audio backend, touch/gamepad) issues
rather than build issues.

## Build details / design decisions

* **`libmain.so`, not an executable.** SDL2's `SDLActivity` calls
  `System.loadLibrary("main")` and `dlsym("SDL_main")`. The patch replaces
  `add_executable(SilentHillPC)` with `add_library(SilentHillPC SHARED)` +
  `OUTPUT_NAME main` on Android, and drops `SDL_MAIN_HANDLED` so `main()` is
  renamed to the exported `SDL_main`.
* **`SH_STATIC_MAPS=ON`.** Android cannot `dlopen()` loose `maps/*.so` from
  app-writable external storage, and the APK's own `lib/` directory is not a
  general-purpose plugin folder. Upstream already has a statically linked
  overlay path (originally for iOS) that prefixes each overlay's symbols with
  `llvm-objcopy`; the patch turns it on by default for Android. Trade-off:
  ~200 MB of `.bss`, hence **arm64-v8a only**.
* **No `OpenGL::GL`.** The NDK provides `GLESv3`, `EGL` and `log`; the patch
  links those instead of `find_package(OpenGL REQUIRED)`.
* **Dependencies are built from source**, not taken from the host.
  `SDL2` and `OpenAL Soft` are shared libs loaded by the Activity (OpenAL stays
  shared for LGPL reasons), `libjpeg-turbo` is static. All are built with an
  explicit `-soname` because CMake disables versioned SONAMEs on Android.
  Cross-compile `find_package()` calls are satisfied by `cmake/FindSDL2.cmake`
  and `cmake/FindOpenAL.cmake`, so a host pkg-config can never leak in.
* **Working directory.** Android starts native code in `/`. `sh_android.c`
  chdirs into `getExternalFilesDir(null)` and creates `gamedata/`,
  `gamedata/save/`, `logs/` and `licenses/` before anything opens a file. The
  Java activity passes `-data <externalFilesDir>/gamedata` to `ParseArgs()`.
* **Single-commit clones.** Only one pinned tree is ever built, so `fetch`
  clones with `--depth 1` (by ref, or by SHA when the pin is a raw commit).
  Full-history clones of these repos are hundreds of megabytes and routinely
  die mid-transfer on slow links, turning a two-minute fetch into a restart.
* **NDK clang is stricter than the compilers this decomp grew up with.** It
  promotes implicit declarations/int conversions and `format-security` to
  errors. `build.sh` relaxes those via `WARN_ARGS` instead of editing thousands
  of decompiled lines; the handful of genuine hard errors (missing prototypes,
  desktop-only GL tokens, an unguarded `__rdtsc()`, an SDL_main shim that
  collides on Android) are fixed in the patches.
* **`extractNativeLibs=true`.** `SDLActivity.getMainSharedObject()` dlopens a
  real path inside `nativeLibraryDir`, so the `.so` files must be extracted;
  both the manifest and `app/build.gradle` enforce this.
* **Assets are a strict whitelist.** `tools/stage.py` copies only the two SIL
  OFL menu fonts, `gamecontrollerdb.txt`, a generated `config.cfg` and the
  licence texts, then audits the result. No disc image, save, log, language
  pack, translation, `.tim` title art or other Konami-derived data ever enters
  the APK. User files are never overwritten on update.

## Installing and playing

```sh
adb install -r dist/SilentHill-Android-debug.apk
```

The app writes `Android/data/com.silenthill.android/files/` on first launch.
Put **your own** BIN/CUE image of Silent Hill (PlayStation, 1999 — the port was
tested with the North American release SLUS-00707 v1.1) into the `gamedata/`
subfolder there. Saves go to `gamedata/save/`, logs to `logs/`.
`config.cfg` is copied once; edits survive updates.

**Input:** the game uses the original PlayStation pad layout. A Bluetooth or
USB gamepad is strongly recommended; SDL's touch-to-mouse mapping only covers
menus, and there is no on-screen virtual pad yet.
Audio uses OpenAL Soft's OpenSL ES backend; SDL's own audio driver is set to
`dummy` so the two do not fight over the output device.

## Known limitations

* This is **build-system support**, not a validated device port. The pipeline
  was executed end to end in Docker and produced a working APK (see
  [Verified build](#verified-build)), and both patches were checked against the
  pristine pinned commits, but nothing has been launched on a device or
  emulator yet. Expect runtime rather than build problems — GLES driver
  quirks, the OpenSL ES audio path, touch/controller mapping — and please
  report them.
* Single screen only: the live bottom-screen inventory/map from the RG DS Plus
  port is not part of this build.
* 64-bit ARM only; `SH_STATIC_MAPS` raises the resident set considerably and
  low-RAM devices may be killed by the LMK.
* FMV overrides that need ffmpeg (`SH_FMV_FFMPEG=OFF`) and
  RetroAchievements (`SH_ENABLE_RETROACHIEVEMENTS=OFF`) are disabled to avoid
  shipping GPL/LGPL binaries and a libcurl dependency. The original PS1
  MDEC/AVI path still works.
* `gradle :app:assembleDebug` produces a **debug-signed** APK. A release build
  needs your own signing config in `app/build.gradle`.
* No game data is included, and requests for game files are out of scope.
  Silent Hill is © Konami.

## Layout

```
android/
  README.md              this file
  Dockerfile             SDK/NDK/Gradle/JDK build image
  build.sh               fetch / deps / game / stage / apk driver
  versions.env           pinned upstream + third-party versions
  patches/               silent-hill-android.patch (upstream tree)
                         psycross-android.patch   (inside the submodule)
  native/                sh_android.c / .h (copied into pc_port at fetch time)
  cmake/                 FindSDL2.cmake, FindOpenAL.cmake
  tools/stage.py         asset whitelist, config overrides, Gradle staging
  app/                   Gradle project (settings.gradle is at android/)
    src/main/            manifest, SilentHillActivity, resources, generated assets
    libs/<abi>/          generated .so files (jniLibs)
    sdl-java/            generated SDL2 Java activity sources
```

## Licence

The Android additions in this directory are offered under **GPL-3.0-or-later**
(see `LICENSE`), consistent with the rest of this repository's own changes.
Third-party components keep their own licences; see the `THIRD-PARTY-NOTICES`
generated into the APK's `licenses/` folder. No decompiled game code is
licensed by this repository.
