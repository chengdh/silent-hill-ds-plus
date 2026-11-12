/* SPDX-License-Identifier: GPL-3.0-or-later */
/*
 * Android startup shim for the Silent Hill PC Port.
 * This header is copied into upstream/pc_port/include/ by android/build.sh.
 */
#ifndef SH_ANDROID_H
#define SH_ANDROID_H

#ifdef __ANDROID__

/* Anchor the process to the app's external files directory and set the SDL /
 * OpenAL hints the game needs. Must be called at the very top of SDL_main(),
 * before config.cfg or gamedata/ are opened. */
void SH_AndroidPrepare(void);

/* Absolute path of the app's external files directory, or "." on failure. */
const char* SH_AndroidBasePath(void);

#endif /* __ANDROID__ */
#endif /* SH_ANDROID_H */
