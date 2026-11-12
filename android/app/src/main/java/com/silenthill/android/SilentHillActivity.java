/* SPDX-License-Identifier: GPL-3.0-or-later */
package com.silenthill.android;

import android.content.Context;
import android.os.Build;
import android.os.Bundle;
import android.util.Log;
import android.view.View;
import android.view.WindowInsets;
import android.view.WindowInsetsController;
import android.view.WindowManager;

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
        // Straight after super.onCreate(), and still before the first layout pass:
        // the surface has to be measured full-screen, otherwise it comes out one
        // status/navigation bar short (1920x1025 on the AYN Thor). SDL keeps the
        // EGL buffer geometry it got at surface creation, so every frame it swaps
        // afterwards is 1025 tall and BufferQueue rejects it -- the game renders
        // correctly but the screen stays black.
        applyImmersiveMode();
    }

    @Override
    public void onWindowFocusChanged(boolean hasFocus) {
        super.onWindowFocusChanged(hasFocus);
        if (hasFocus) {
            // A transient bar can come back (notification shade, IME); re-hide it
            // before the surface is re-measured.
            applyImmersiveMode();
        }
    }

    /** Edge-to-edge, no status/navigation bar, and lay out into a display cutout. */
    private void applyImmersiveMode() {
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN);

        // The legacy flags still do the work on this device and are harmless on
        // newer releases; the insets controller is what actually pins it down.
        View decor = getWindow().getDecorView();
        decor.setSystemUiVisibility(
                View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                        | View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                        | View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                        | View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                        | View.SYSTEM_UI_FLAG_FULLSCREEN
                        | View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY);

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            getWindow().setDecorFitsSystemWindows(false);
            WindowInsetsController controller = decor.getWindowInsetsController();
            if (controller != null) {
                controller.hide(WindowInsets.Type.statusBars() | WindowInsets.Type.navigationBars());
                controller.setSystemBarsBehavior(
                        WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE);
            }
        }
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
