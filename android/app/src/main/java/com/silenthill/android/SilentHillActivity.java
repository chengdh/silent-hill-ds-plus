/* SPDX-License-Identifier: GPL-3.0-or-later */
package com.silenthill.android;

import android.content.Context;
import android.os.Bundle;
import android.util.Log;

import org.libsdl.app.SDLActivity;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;

/**
 * SDL2 entry point for the Android build.
 *
 * The native side is libmain.so (the upstream pc_port built as a shared
 * library). SDL2 and OpenAL Soft are separate shared libraries loaded first;
 * libjpeg is linked statically. The app's external files directory is the
 * game's working directory: config.cfg, gamedata/ and the logs all live there.
 */
public class SilentHillActivity extends SDLActivity {

    private static final String TAG = "SilentHill";

    /** Load order matters: libc++ is a dependency of everything else. */
    @Override
    protected String[] getLibraries() {
        return new String[] { "c++_shared", "SDL2", "openal", "main" };
    }

    /** Parsed by ParseArgs() in main_pc.c; argv[0] is supplied by SDL. */
    @Override
    protected String[] getArguments() {
        File base = getExternalFilesDir(null);
        if (base == null) {
            Log.e(TAG, "external files directory is unavailable");
            return new String[0];
        }
        return new String[] { "-data", new File(base, "gamedata").getAbsolutePath() };
    }

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        // Must happen before super.onCreate(), which loads libmain.so.
        installAssets();
        super.onCreate(savedInstanceState);
    }

    /** Only files that are missing are copied: never overwrite user settings
     *  or anything the player placed in gamedata/. */
    private void installAssets() {
        File base = getExternalFilesDir(null);
        if (base == null) {
            return;
        }
        mkdir(new File(base, "gamedata"));
        mkdir(new File(base, "gamedata/font"));
        mkdir(new File(base, "gamedata/save"));
        mkdir(new File(base, "logs"));
        mkdir(new File(base, "licenses"));

        String[] files = {
                "config.cfg",
                "gamecontrollerdb.txt",
                "README-ANDROID.txt",
                "gamedata/PUT-YOUR-GAME-HERE.txt",
                "gamedata/font/BarlowSemiCondensed-Regular.ttf",
                "gamedata/font/Oswald-Regular.ttf",
                "licenses/LICENSE",
                "licenses/COPYRIGHT",
                "licenses/THIRD-PARTY-NOTICES",
                "licenses/OFL.txt",
                "licenses/LICENSE-SDL_GameControllerDB.txt"
        };
        for (String name : files) {
            copyIfMissing(this, name, new File(base, name));
        }
    }

    private static void mkdir(File dir) {
        if (!dir.isDirectory() && !dir.mkdirs()) {
            Log.w(TAG, "could not create " + dir.getAbsolutePath());
        }
    }

    private static void copyIfMissing(Context context, String asset, File target) {
        if (target.exists()) {
            return;
        }
        File parent = target.getParentFile();
        if (parent != null) {
            mkdir(parent);
        }
        try (InputStream in = context.getAssets().open(asset);
             OutputStream out = new FileOutputStream(target)) {
            byte[] buffer = new byte[64 * 1024];
            int n;
            while ((n = in.read(buffer)) > 0) {
                out.write(buffer, 0, n);
            }
        } catch (IOException e) {
            Log.e(TAG, "could not install asset " + asset, e);
        }
    }
}
