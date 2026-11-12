/* SPDX-License-Identifier: GPL-3.0-or-later */
/*
 * Android startup shim for the Silent Hill PC Port.
 *
 * SDL2's Android activity starts native code with cwd = "/" and no usable
 * HOME. The PC port loads config.cfg, writes SilentHill_*.log and resolves
 * gamedata/ through relative paths, so the working directory has to be
 * anchored to the app's own external files directory before main() does
 * anything else. SH_AndroidPrepare() is called from main_pc.c at the top of
 * SDL_main(); see patches/silent-hill-android.patch.
 *
 * This file is copied into upstream/pc_port/src/ by android/build.sh and is
 * picked up automatically by the existing recursive glob over that directory.
 */
#ifdef __ANDROID__

#include "sh_android.h"

#include <SDL.h>
#include <SDL_system.h>
#include <android/log.h>
#include <errno.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#define SH_ANDROID_TAG "SilentHill"

static char s_base[PATH_MAX] = ".";

const char* SH_AndroidBasePath(void)
{
    return s_base;
}

static void SH_AndroidMkdir(const char* path)
{
    if (mkdir(path, 0777) != 0 && errno != EEXIST)
        __android_log_print(ANDROID_LOG_WARN, SH_ANDROID_TAG,
                            "mkdir(%s) failed", path);
}

static void SH_AndroidMkdirUnder(const char* suffix)
{
    char path[PATH_MAX];
    snprintf(path, sizeof(path), "%s/%s", s_base, suffix);
    SH_AndroidMkdir(path);
}

void SH_AndroidPrepare(void)
{
    const char* external = SDL_AndroidGetExternalStoragePath();
    if (!external || !external[0])
    {
        __android_log_print(ANDROID_LOG_ERROR, SH_ANDROID_TAG,
                            "SDL_AndroidGetExternalStoragePath() returned nothing; "
                            "config.cfg and gamedata/ will not be found");
        return;
    }

    snprintf(s_base, sizeof(s_base), "%s", external);
    if (chdir(s_base) != 0)
        __android_log_print(ANDROID_LOG_ERROR, SH_ANDROID_TAG,
                            "chdir(%s) failed", s_base);

    /* The game expects these to exist. Never touch anything the player put
     * there: a missing disc image is reported by the game itself. */
    SH_AndroidMkdirUnder("gamedata");
    SH_AndroidMkdirUnder("gamedata/font");
    SH_AndroidMkdirUnder("gamedata/save");
    SH_AndroidMkdirUnder("logs");
    SH_AndroidMkdirUnder("licenses");

    /* PsyCross draws through SDL's GLES3 window; SDL's own audio driver is not
     * used (PsyCross talks to OpenAL Soft directly), so keep it out of the way
     * of the OpenSL ES backend and of Bluetooth gamepads. */
    /* Orientation is fixed to landscape in AndroidManifest.xml. */
    SDL_SetHint(SDL_HINT_ACCELEROMETER_AS_JOYSTICK, "0");
    SDL_SetHint(SDL_HINT_JOYSTICK_ALLOW_BACKGROUND_EVENTS, "1");
    SDL_SetHint(SDL_HINT_TOUCH_MOUSE_EVENTS, "1");
    SDL_SetHint(SDL_HINT_MOUSE_TOUCH_EVENTS, "0");
    setenv("SDL_AUDIODRIVER", "dummy", 0);
    setenv("SH_ANDROID", "1", 0);

    __android_log_print(ANDROID_LOG_INFO, SH_ANDROID_TAG,
                        "data root: %s (cwd set)", s_base);
}

#endif /* __ANDROID__ */
