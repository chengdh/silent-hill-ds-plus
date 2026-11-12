#!/usr/bin/env python3
"""Stage everything the Android Gradle project needs from the native build.

Called by android/build.sh once per ABI. Deliberately mirrors the RG DS Plus
packaging rule: no disc image, no save, no log, and none of the Konami-derived
assets in upstream pc_port/assets/gamedata ever enter the APK. Only the two
SIL OFL menu fonts, the game controller database, config.cfg and licence texts
are shipped. The player supplies their own BIN/CUE at runtime.
"""
# SPDX-License-Identifier: GPL-3.0-or-later
import argparse
import re
import shutil
import sys
from pathlib import Path

ap = argparse.ArgumentParser(description=__doc__)
ap.add_argument('--root', required=True, help='repository root (contains android/ and upstream sources)')
ap.add_argument('--work', required=True, help='android build work directory')
ap.add_argument('--abi', required=True, help='Android ABI, e.g. arm64-v8a')
ap.add_argument('--deps', required=True, help='per-ABI dependency prefix')
ap.add_argument('--build', required=True, help='per-ABI pc_port CMake build directory')
ap.add_argument('--ndk', required=True, help='Android NDK root')
args = ap.parse_args()

root = Path(args.root).resolve()
work = Path(args.work).resolve()
upstream = work / 'upstream'
pc_port = upstream / 'pc_port'
app = root / 'android' / 'app'
assets = app / 'src' / 'main' / 'assets'
jni = app / 'libs' / args.abi
sdl_java = app / 'sdl-java' / 'org' / 'libsdl' / 'app'
deps = Path(args.deps).resolve()
build = Path(args.build).resolve()
ndk = Path(args.ndk).resolve()

# No game data may ever be bundled. Keep the same exclusion list as package.py.
FORBIDDEN = ('.bin', '.cue', '.iso', '.chd', '.pbp', '.img', '.mcd', '.mdf', '.log')


def fail(msg):
    sys.exit('stage.py: ' + msg)


def copy(source, target):
    if not source.is_file():
        fail(f'missing {source}')
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, target)


# ---------------------------------------------------------------------------
# SDL2's Java activity sources. Copied from the pinned SDL2 checkout rather
# than vendored, so their licence and version always match libSDL2.so.
# ---------------------------------------------------------------------------
sdl_src = work / 'third_party' / 'SDL' / 'android-project' / 'app' / 'src' / 'main' / 'java' / 'org' / 'libsdl' / 'app'
java_files = sorted(sdl_src.glob('*.java')) if sdl_src.is_dir() else []
if len(java_files) < 9:
    fail(f'expected SDL2 android-project Java sources under {sdl_src}')
sdl_java.mkdir(parents=True, exist_ok=True)
for f in sdl_java.glob('*.java'):
    f.unlink()
for f in java_files:
    copy(f, sdl_java / f.name)

# ---------------------------------------------------------------------------
# Native libraries -> app/libs/<abi> (Gradle jniLibs).
# ---------------------------------------------------------------------------
libs = [
    (deps / 'lib' / 'libSDL2.so', jni / 'libSDL2.so'),
    (deps / 'lib' / 'libopenal.so', jni / 'libopenal.so'),
    (build / 'libmain.so', jni / 'libmain.so'),
]
# libc++_shared.so is needed because every library uses ANDROID_STL=c++_shared.
triple = {'arm64-v8a': 'aarch64-linux-android',
          'armeabi-v7a': 'arm-linux-androideabi',
          'x86_64': 'x86_64-linux-android',
          'x86': 'i686-linux-android'}.get(args.abi)
if not triple:
    fail(f'unsupported ABI {args.abi}')
libcxx = list(ndk.glob(f'toolchains/llvm/prebuilt/*/sysroot/usr/lib/{triple}/libc++_shared.so'))
if not libcxx:
    fail(f'cannot find libc++_shared.so for {triple} under {ndk}')
libs.append((libcxx[0], jni / 'libc++_shared.so'))

for source, target in libs:
    copy(source, target)

# ---------------------------------------------------------------------------
# APK assets: explicit whitelist, never a recursive copy of gamedata/.
# ---------------------------------------------------------------------------
upstream_assets = pc_port / 'assets'
font_names = ('BarlowSemiCondensed-Regular.ttf', 'Oswald-Regular.ttf')

copy(upstream_assets / 'gamecontrollerdb.txt', assets / 'gamecontrollerdb.txt')
for name in font_names:
    copy(upstream_assets / 'gamedata' / 'font' / name, assets / 'gamedata' / 'font' / name)
copy(upstream_assets / 'licenses' / 'OFL.txt', assets / 'licenses' / 'OFL.txt')
copy(upstream_assets / 'licenses' / 'LICENSE-SDL_GameControllerDB.txt',
     assets / 'licenses' / 'LICENSE-SDL_GameControllerDB.txt')
copy(root / 'LICENSE', assets / 'licenses' / 'LICENSE')
copy(root / 'COPYRIGHT.md', assets / 'licenses' / 'COPYRIGHT')

# config.cfg with Android-safe overrides. Same regex-override approach as the
# RG DS Plus package.py; missing keys are appended.
config = (pc_port / 'config.cfg').read_text(encoding='utf-8')
overrides = {
    'renderer': 'gles',            # PsyCross uses the fixed GLES3 path on Android anyway
    'windowWidth': '1280',
    'windowHeight': '720',
    'fullscreen': '0',
    'fps_cap': '30',
    'native_resolution': '0',
    'msaa': '0',
    'preload_chunks': '0',         # no disc image is known at install time
    'enable_plugins': '0',
    'show_console': '0',
    'enable_debug_log': '1',
    'discord_rich_presence': '0',  # no desktop Discord client to reach
    'skip_intros': '1',
    'config_version': '3',
}
for key, value in overrides.items():
    pattern = rf'(?m)^{re.escape(key)}\s*=.*$'
    line = f'{key} = {value}'
    config = re.sub(pattern, line, config) if re.search(pattern, config) else config + '\n' + line + '\n'
(assets / 'config.cfg').parent.mkdir(parents=True, exist_ok=True)
(assets / 'config.cfg').write_text(config, encoding='utf-8')

(assets / 'README-ANDROID.txt').write_text(
    'Silent Hill - Android native port\n'
    '================================\n\n'
    'This app contains NO game data. You need your own copy of Silent Hill\n'
    '(PlayStation, 1999); Silent Hill and its content are (c) Konami.\n\n'
    'Make a BIN/CUE image from your own disc where the law allows it, then put\n'
    'the .bin and .cue files into this app\'s external files directory, in the\n'
    'gamedata/ subfolder next to PUT-YOUR-GAME-HERE.txt. That directory is:\n\n'
    '  Android/data/com.silenthill.android/files/\n\n'
    'Saves go to gamedata/save/, logs to logs/. config.cfg is only written on\n'
    'first launch so your edits survive an update. Logs are useful when filing\n'
    'a bug report. Connect a Bluetooth/USB gamepad: the game is built around\n'
    'the original PlayStation pad layout, and touch input only drives menus.\n\n'
    'This is an unofficial, non-commercial fan project, not affiliated with or\n'
    'endorsed by Konami. See licenses/ for the full licence texts.\n',
    encoding='utf-8')

(assets / 'gamedata' / 'PUT-YOUR-GAME-HERE.txt').write_text(
    'Put your own Silent Hill (USA, SLUS-00707) .bin and .cue files here.\n'
    'No disc image, BIOS, music, video, texture or text is included in this app.\n',
    encoding='utf-8')

(assets / 'licenses' / 'THIRD-PARTY-NOTICES').write_text(
    'Third-party notices for the Silent Hill Android port\n'
    '===================================================\n\n'
    'The APK contains no game data. It is a native build of the Silent Hill PC\n'
    'Port (https://github.com/SlickAmogus/silent-hill-decomp, branch pc-port)\n'
    'at the commit pinned in android/versions.env, plus this repository\'s\n'
    'Android build support (GPL-3.0-or-later).\n\n'
    'Compiled into libmain.so\n'
    '  - PsyCross (PS1 hardware abstraction): MIT.\n'
    '  - Lua 5.4, miniz, cgltf/jsmn, stb_image/stb_truetype, xxHash, bcdec,\n'
    '    glad 0.1.36, the Shinonome bitmap font and the REDRIVER2-derived FMV\n'
    '    player / BSD-3-Clause AVI reader: see the upstream sources and the\n'
    '    RG DS Plus archive\'s THIRD-PARTY-NOTICES for the full licence texts.\n'
    '  - An MDEC decoder adapted from FFmpeg (LGPL-2.1-or-later, used under\n'
    '    GPL-3.0-or-later as allowed by LGPL section 3).\n'
    '  - libjpeg-turbo (IJG / BSD-style licences): linked statically, used for\n'
    '    MJPG frames in the FMV player.\n'
    '  - Oswald and Barlow Semi Condensed fonts: SIL Open Font License 1.1\n'
    '    (licenses/OFL.txt).\n'
    '  - SDL_GameControllerDB: zlib (licenses/LICENSE-SDL_GameControllerDB.txt).\n\n'
    'Separate shared libraries in the APK\n'
    '  - SDL2 2.32.10: zlib licence.\n'
    '  - OpenAL Soft 1.25.2 (OpenSL ES backend): LGPL-2.1-or-later. It stays a\n'
    '    separate shared library so it can be replaced/relinked.\n'
    '  - libc++_shared.so from the Android NDK: Apache-2.0 with LLVM exception.\n\n'
    'Corresponding source for this build is the pinned upstream commit plus\n'
    'the patches and build scripts in this repository.\n',
    encoding='utf-8')

# Audit: no disc images, saves, logs or Konami-derived assets may be staged.
staged = sorted(p for p in assets.rglob('*') if p.is_file())
bad = [p for p in staged if p.name.lower().endswith(FORBIDDEN)]
gamedata = sorted(str(p.relative_to(assets)) for p in staged if p.relative_to(assets).parts[0] == 'gamedata')
expected = sorted(['gamedata/PUT-YOUR-GAME-HERE.txt'] +
                  [f'gamedata/font/{n}' for n in font_names])
if bad or gamedata != expected:
    fail(f'asset audit failed: forbidden={bad} gamedata={gamedata}')

print(f'Staged {len(java_files)} SDL2 Java sources, {len(libs)} native libraries, '
      f'{len(staged)} assets for {args.abi}')
