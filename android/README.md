# Android build support (experimental)

> 快速开始：这是给本仓库新增的 **Android 原生构建链**，与原 RG DS Plus 的 Wayland 双屏构建完全独立、互不影响。
> 需要 Android SDK / NDK 27、JDK 17、Gradle 8.7+、CMake、Ninja、Python 3。
> 最省事的方式：`docker build -t sh-android-builder -f android/Dockerfile android`，
> 然后 `docker run --rm -v "$PWD":/work -w /work/silent-hill sh-android-builder sh android/build.sh all`。
> 产物在 `dist/SilentHill-Android-debug.apk`。**APK 不含任何游戏数据**，需要你自己准备 Silent Hill 光盘镜像。

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
  + patches/silent-hill-android.patch   (this directory, 2 files, 7 hunks)
  + native/sh_android.{c,h}             (startup shim)
        |
        v  NDK CMake toolchain -> libmain.so  (SDL_main entry point)
        |
        v  SDL2 Activity (org.libsdl.app) + OpenAL Soft + static libjpeg
        |
        v  Gradle -> app-debug.apk
```

Upstream PsyCross already contains a fixed-target `__ANDROID__` /
`RENDERER_OGLES` / `OGLES_VERSION=3` path, so no renderer port is needed here;
the work is almost entirely build-system and platform plumbing.

The original `tools/build.sh`, `tools/package.py` and both `*-rgds.patch`
files are **not modified**. Both builds can coexist in the same checkout.

## Prerequisites

| Tool | Version |
| --- | --- |
| Android SDK | platform android-34, build-tools 34.0.0, platform-tools |
| Android NDK | `27.2.12479018` |
| JDK | 17 |
| Gradle | 8.7+ (8.9 in the Dockerfile) |
| CMake / Ninja / Python 3 / git | recent |

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

The supplied `Dockerfile` installs the SDK, NDK, Gradle and JDK; it only needs
network access for the SDK download, the git clones and the Android Gradle
Plugin on the first Gradle run.

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
  was assembled against the pinned upstream sources and statically checked
  (patch applies cleanly, scripts and manifests parsed), but no Android device
  build/run was performed while adding it. Expect driver- and NDK-specific
  fixes on the first real compile and please report them.
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
  patches/               silent-hill-android.patch (applied to upstream)
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
