package com.azesmwayreactnativeunity;

import android.app.Activity;
import android.graphics.PixelFormat;
import android.os.Build;
import android.util.Log;
import android.view.ViewGroup;
import android.view.WindowManager;

import static android.view.ViewGroup.LayoutParams.MATCH_PARENT;

import java.lang.reflect.InvocationTargetException;

public class ReactNativeUnity {
    private static final String TAG = "ReactNativeUnity";
    // Diagnostic startup/message timing (logcat tag "RNUnityTiming").
    // Set false for production — this is for tracing the embedded load path.
    public static final boolean DEBUG_TIMING = true;
    static final String TIMING_TAG = "RNUnityTiming";
    // Blocking wait (ms) between constructing the UnityPlayer and attaching it.
    // Load-bearing: fixes "unity cannot start when startup" on Android. Must stay
    // a blocking sleep on the UI thread — making it a non-blocking post regressed
    // startup so Unity never booted (no surface attach).
    private static final long UNITY_STARTUP_DELAY_MS = 1000;
    private static UPlayer unityPlayer;
    public static boolean _isUnityReady;
    public static boolean _isUnityPaused;
    public static boolean _fullScreen;

    public static UPlayer getPlayer() {
        if (!_isUnityReady) {
            return null;
        }
        return unityPlayer;
    }

    public static boolean isUnityReady() {
        return _isUnityReady;
    }

    public static boolean isUnityPaused() {
        return _isUnityPaused;
    }

    public static void createPlayer(final Activity activity, final UnityPlayerCallback callback) throws InvocationTargetException, NoSuchMethodException, IllegalAccessException {
        if (unityPlayer != null) {
            callback.onReady();

            return;
        }

        if (activity == null) {
            return;
        }

        activity.runOnUiThread(new Runnable() {
            @Override
            public void run() {
                if (DEBUG_TIMING) Log.i(TIMING_TAG, "createPlayer.run begin on thread=" + Thread.currentThread().getName());
                activity.getWindow().setFormat(PixelFormat.RGBA_8888);
                int flag = activity.getWindow().getAttributes().flags;
                boolean fullScreen =
                    (flag & WindowManager.LayoutParams.FLAG_FULLSCREEN) == WindowManager.LayoutParams.FLAG_FULLSCREEN;

                try {
                    unityPlayer = new UPlayer(activity, callback);
                } catch (ClassNotFoundException | InstantiationException | IllegalAccessException | InvocationTargetException e) {
                    Log.e(TAG, "Failed to create Unity player", e);
                }

                if (unityPlayer == null) {
                    // Construction failed (already logged). Bail instead of
                    // NPE-ing on the calls below.
                    return;
                }
                if (DEBUG_TIMING) Log.i(TIMING_TAG, "UnityPlayer constructed");

                try {
                    // Load-bearing blocking wait: fixes "unity cannot start when
                    // startup". Do NOT replace with a non-blocking post — that
                    // regresses startup so Unity never boots / attaches a surface.
                    Thread.sleep(UNITY_STARTUP_DELAY_MS);
                } catch (Exception e) {}

                if (DEBUG_TIMING) Log.i(TIMING_TAG, "attach begin on thread=" + Thread.currentThread().getName());

                // start unity
                try {
                    addUnityViewToBackground();
                } catch (InvocationTargetException | IllegalAccessException | NoSuchMethodException e) {
                    Log.e(TAG, "Failed to add Unity view to background", e);
                }

                unityPlayer.windowFocusChanged(true);

                try {
                    unityPlayer.requestFocusPlayer();
                } catch (NoSuchMethodException | IllegalAccessException | InvocationTargetException e) {
                    Log.e(TAG, "Failed to request focus on Unity player", e);
                }

                unityPlayer.resume();

                if (!fullScreen) {
                    activity.getWindow().addFlags(WindowManager.LayoutParams.FLAG_FORCE_NOT_FULLSCREEN);
                    activity.getWindow().clearFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN);
                }

                _isUnityReady = true;
                if (DEBUG_TIMING) Log.i(TIMING_TAG, "_isUnityReady=true; invoking onReady (player attached + resumed)");

                try {
                    callback.onReady();
                } catch (InvocationTargetException | IllegalAccessException | NoSuchMethodException e) {
                    Log.e(TAG, "Unity onReady callback failed", e);
                }
            }
        });
    }

    public static void pause() {
        if (unityPlayer != null) {
            unityPlayer.pause();
            _isUnityPaused = true;
        }
    }

    public static void resume() {
        if (unityPlayer != null) {
            unityPlayer.resume();
            _isUnityPaused = false;
        }
    }

    public static void unload() {
        if (unityPlayer != null) {
            unityPlayer.unload();
            _isUnityPaused = false;
        }
    }

    public static void destroy() {
        if (unityPlayer != null) {
            unityPlayer.destroy();
        }
        // Drop the reference and reset state so a later mount recreates a fresh
        // player instead of handing back a destroyed one.
        unityPlayer = null;
        _isUnityReady = false;
        _isUnityPaused = false;
    }

    public static void addUnityViewToBackground() throws InvocationTargetException, NoSuchMethodException, IllegalAccessException {
        if (unityPlayer == null) {
            return;
        }

        if (unityPlayer.getParentPlayer() != null) {
            // NOTE: If we're being detached as part of the transition, make sure
            // to explicitly finish the transition first, as it might still keep
            // the view's parent around despite calling `removeView()` here. This
            // prevents a crash on an `addContentView()` later on.
            // Otherwise, if there's no transition, it's a no-op.
            // See https://stackoverflow.com/a/58247331
            ((ViewGroup) unityPlayer.getParentPlayer()).endViewTransition(unityPlayer.requestFrame());
            ((ViewGroup) unityPlayer.getParentPlayer()).removeView(unityPlayer.requestFrame());
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            unityPlayer.setZ(-1f);
        }

        final Activity activity = ((Activity) unityPlayer.getContextPlayer());
        ViewGroup.LayoutParams layoutParams = new ViewGroup.LayoutParams(1, 1);
        activity.addContentView(unityPlayer.requestFrame(), layoutParams);
    }

    public static void addUnityViewToGroup(ViewGroup group) throws NoSuchMethodException, InvocationTargetException, IllegalAccessException {
        if (unityPlayer == null) {
            return;
        }

        if (unityPlayer.getParentPlayer() != null) {
            // NOTE: If we're being detached as part of the transition, make sure
            // to explicitly finish the transition first, as it might still keep
            // the view's parent around despite calling `removeView()` here. This
            // prevents a crash on an `addView()` later on.
            // Otherwise, if there's no transition, it's a no-op.
            // See https://stackoverflow.com/a/58247331
            ((ViewGroup) unityPlayer.getParentPlayer()).endViewTransition(unityPlayer.requestFrame());
            ((ViewGroup) unityPlayer.getParentPlayer()).removeView(unityPlayer.requestFrame());
        }

        ViewGroup.LayoutParams layoutParams = new ViewGroup.LayoutParams(MATCH_PARENT, MATCH_PARENT);
        group.addView(unityPlayer.requestFrame(), 0, layoutParams);
        unityPlayer.windowFocusChanged(true);
        unityPlayer.requestFocusPlayer();
        unityPlayer.resume();
    }

    public interface UnityPlayerCallback {
        void onReady() throws InvocationTargetException, NoSuchMethodException, IllegalAccessException;

        void onUnload();

        void onQuit();
    }
}
