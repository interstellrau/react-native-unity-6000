# Android cold-start: Unity view takes ~30s on first launch

Brief for the Unity team. The React Native bridge is **not** the cause; the fix
is a small change in the Unity startup coroutine (plus an optional RN-side
splash tweak).

## TL;DR
On a **cold** app launch, `UnityReady` is gated on `WaitForEndOfFrame`, which
cannot complete while the React Native splash overlay occludes the Unity
`SurfaceView` — so it blocks ~22–23s every cold boot. **Fix:** send `UnityReady`
as soon as the scene/mannequin content is built, without waiting for a
presented frame.

## Symptom
| Scenario | Unity ready |
| --- | --- |
| Cold first launch | ~33s |
| Warm re-mount (same process) | ~6–7s |
| Standalone Unity build (no RN) | ~3s |

## Evidence (from the app's own `[Ustyler]` startup markers)

**Cold boot:**
```
[Ustyler] Startup: engine ready ... at 8.04s
[Ustyler] Startup: first scene LOADED ... at 8.11s
[Ustyler] <<< wait DesignController+mannequin END +2291 ms      (at 10.39s)
[Ustyler] >>> WaitForEndOfFrame START at 10.39s
[Ustyler] <<< WaitForEndOfFrame END +23044 ms                  <-- the entire delay
[Ustyler] UnityReady at 33.44s
[Ustyler] WATCHDOG: frame 2 ... +23091 ms since prev frame
```

**Warm re-mount (same content, same device):**
```
[Ustyler] <<< WaitForEndOfFrame END +66 ms
[Ustyler] UnityReady at 6.15s
```

The only thing that explodes on cold boot is `WaitForEndOfFrame`. Everything
else is within ~2s. So the cold delay is 100% a first-frame **presentation**
wait — not engine init, scene load, or shader compilation (the Vulkan pipeline
cache loads fine, and the warm path proves the same yield returns in 66ms).

## Root cause: vsync starvation while the splash occludes Unity
- The startup coroutine yields `WaitForEndOfFrame`, which only resumes after
  Unity renders **and presents** a frame.
- On cold boot the RN splash overlay sits opaque over the Unity `SurfaceView`.
  Android does not composite a fully-occluded `SurfaceView`, so Unity's surface
  receives **no vsync** and the player loop cannot advance —
  `WaitForEndOfFrame` hangs.
- The RN side keeps the splash up until it receives `UnityReady`. So: splash
  waits for `UnityReady` → `UnityReady` waits for a presented frame → the frame
  can't present while the splash occludes it. **Circular wait**, broken only
  when the splash is eventually removed (~23s).
- Warm re-mounts reuse a preserved surface
  (`PersistentUnitySurface.preserveContent`) and never re-enter that state → 66ms.

## Fix (Unity side — primary)
In the startup coroutine, find the `yield return new WaitForEndOfFrame();` that
sits between the `wait DesignController+mannequin END` step and the `UnityReady`
send (it's the line that logs `[Ustyler] >>> WaitForEndOfFrame START`). Remove
that gate — send `UnityReady` as soon as the content is built.

**Before (conceptual):**
```csharp
// ... build DesignController + mannequin, apply stencil / fabric ...
yield return new WaitForEndOfFrame();        // hangs ~23s on cold boot
SendToReact("UnityReady", "Unity is fully initialized");
```

**After:**
```csharp
// ... build DesignController + mannequin, apply stencil / fabric ...
// Content is ready here. Do NOT wait for a presented frame: on a cold boot the
// RN splash occludes the Unity SurfaceView, Android withholds vsync, and
// WaitForEndOfFrame can't complete until the splash is gone. Signal readiness
// now; dismissing the splash lets Unity become visible and start presenting.
SendToReact("UnityReady", "Unity is fully initialized");
yield break;
```

After this change, `UnityReady` fires at ~10s. The RN side dismisses the splash,
the `SurfaceView` un-occludes, vsync starts, and Unity renders. You will **not**
see a black screen — Unity appears as the splash lifts.

## Complementary fix (React Native side)
To guarantee Unity is never starved of vsync during startup (and to avoid any
first-frame flash), don't render the splash as an opaque view fully covering
`<UnityView>`:
- render the splash as a **translucent** overlay, or
- **cross-fade** it out on `UnityReady` instead of a hard cut, or
- keep it as a sibling that doesn't fully cover the Unity view region.

This keeps the `SurfaceView` composited (so it presents while still loading),
meaning even a retained `WaitForEndOfFrame` would complete immediately.

## Secondary (optional, after the above)
Even warm, Unity engine-ready is ~6–8s vs ~3s standalone. The extra is largely
React Native's cold-start contending with Unity init on the same device. Lower
priority once the 22s is gone; options: defer mounting `<UnityView>` until the
RN screen has settled, or reduce concurrent RN startup work / network on launch.

## How to verify
Re-export with the change and check the same `[Ustyler]` markers on a **cold**
boot:
- `UnityReady` now appears at ~10s (not ~33s).
- The `WaitForEndOfFrame` gap is gone (or tens of ms).
