package com.azesmwayreactnativeunity;

import static com.azesmwayreactnativeunity.ReactNativeUnity.*;

import android.content.Context;

import android.annotation.SuppressLint;
import android.content.res.Configuration;
import android.util.Log;
import android.widget.FrameLayout;

import java.lang.reflect.InvocationTargetException;

@SuppressLint("ViewConstructor")
public class ReactNativeUnityView extends FrameLayout {
  private UPlayer view;
  public boolean keepPlayerMounted = false;

  public ReactNativeUnityView(Context context) {
    super(context);
  }

  public void setUnityPlayer(UPlayer player) throws InvocationTargetException, NoSuchMethodException, IllegalAccessException {
    if (DEBUG_TIMING) Log.i(TIMING_TAG, "setUnityPlayer -> addUnityViewToGroup (view " + getWidth() + "x" + getHeight()
        + " vis=" + getVisibility() + " attached=" + isAttachedToWindow() + " windowVis=" + getWindowVisibility() + ")");
    this.view = player;
    addUnityViewToGroup(this);
  }

  @Override
  protected void onAttachedToWindow() {
    super.onAttachedToWindow();
    if (DEBUG_TIMING) Log.i(TIMING_TAG, "View.onAttachedToWindow " + getWidth() + "x" + getHeight()
        + " vis=" + getVisibility() + " windowVis=" + getWindowVisibility());
  }

  @Override
  protected void onWindowVisibilityChanged(int visibility) {
    super.onWindowVisibilityChanged(visibility);
    if (DEBUG_TIMING) Log.i(TIMING_TAG, "View.onWindowVisibilityChanged=" + visibility + " (0=VISIBLE 4=INVISIBLE 8=GONE)");
  }

  @Override
  protected void onSizeChanged(int w, int h, int oldw, int oldh) {
    super.onSizeChanged(w, h, oldw, oldh);
    if (DEBUG_TIMING) Log.i(TIMING_TAG, "View.onSizeChanged " + w + "x" + h);
  }

  @Override
  public void onWindowFocusChanged(boolean hasWindowFocus) {
    super.onWindowFocusChanged(hasWindowFocus);

    if (DEBUG_TIMING) Log.i(TIMING_TAG, "View.onWindowFocusChanged=" + hasWindowFocus
        + " attached=" + isAttachedToWindow() + " " + getWidth() + "x" + getHeight() + " vis=" + getVisibility());

    if (view == null) {
      return;
    }

    view.windowFocusChanged(hasWindowFocus);

    if (!keepPlayerMounted || !_isUnityReady) {
      return;
    }

    // pause Unity on blur, resume on focus
    // if (hasWindowFocus && _isUnityPaused) {
    //   // view.requestFocus();
    //   view.resume();
    // } else if (!hasWindowFocus && !_isUnityPaused) {
    //   view.pause();
    // }
  }

  @Override
  protected void onConfigurationChanged(Configuration newConfig) {
    super.onConfigurationChanged(newConfig);

    if (view != null) {
      view.configurationChanged(newConfig);
    }
  }

  @Override
  protected void onDetachedFromWindow() {
    if (DEBUG_TIMING) Log.i(TIMING_TAG, "View.onDetachedFromWindow keepMounted=" + keepPlayerMounted);
    if (!this.keepPlayerMounted) {
        try {
            addUnityViewToBackground();
        } catch (InvocationTargetException | NoSuchMethodException | IllegalAccessException e) {
            // Don't crash the app on a detach-time race (e.g. during a screen
            // transition); the move-to-background is best-effort.
            Log.e("ReactNativeUnity", "Failed to move Unity view to background on detach", e);
        }
    }

    super.onDetachedFromWindow();
  }
}
