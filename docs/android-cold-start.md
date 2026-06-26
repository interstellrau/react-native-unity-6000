# Android cold-start: Unity stalls ~24s after `UnityReady` (first launch)

Brief for the Unity team. The React Native bridge is **not** the cause — a
Perfetto trace localises the stall to a **blocking loop on Unity's main thread**
that runs *after* `UnityReady`, before the first `Main Camera` render. Fix is
Unity-side.

> Supersedes an earlier version of this note that blamed `WaitForEndOfFrame` /
> splash occlusion. That theory was **disproven** by the trace below — presents
> work during the splash, and the stall is CPU-bound main-thread work, not a
> presentation wait.

## TL;DR
On a cold launch, between sending `UnityReady` and the first `Main Camera`
render, `UnityMain` runs a **~24-second blocking poll/compute loop** (~2,600
iterations) that never yields to the engine, so no frames render until it exits
on a timeout. Standalone the same build does this in ~2s. Convert the blocking
loop into a coroutine that **yields each iteration** (or render defaults
immediately and apply host data when it arrives).

## Symptom
| Scenario | First camera render |
| --- | --- |
| Cold first launch, embedded | ~34s (`UnityReady` ~11s + ~24s stall) |
| Warm re-mount (same process) | ~6–7s |
| Standalone Unity build (no RN) | ~2–3s |

## Evidence (Perfetto, cold boot, Pixel 6 Pro, bare full-screen `<UnityView>`)
The freeze is the span from `UnityReady` to `RENDER Main Camera frame 1` — the
player loop is frozen the whole time (the app's own `WATCHDOG` logs frame 1 →
frame 2 as **+24,000 ms**).

`UnityMain` thread, measured over the freeze window:

| Metric | Value | What it rules out |
| --- | --- | --- |
| **Running** | ~21,000 ms | — it is CPU-bound (doing work) |
| Sleeping (self-timed, **null** waker) | ~8,800 ms | short poll sleeps, not waiting on another thread |
| **Runnable** (waiting for a CPU) | **~99 ms** | CPU contention / starvation |
| Cores used | **CPU 6 & 7 only** (Cortex-X1 prime) | little-core / scheduling throttle |
| Woken by `Loading.AsyncRead` | ~5 ms total | an asset-loading stall |
| `Loading.AsyncRead` own state | asleep ~18.4 s | the loader being the bottleneck |

Derived shape of the loop (from slice counts): **~2,600 iterations of ~8 ms
compute + ~3.5 ms sleep**, on the prime cores, blocking rendering. It
self-releases at ~24 s (a **timeout**) on a stripped test screen; in the full
app the release sometimes coincides with a later navigation event.

## What it is NOT (each disproven directly)
- **Not the RN bridge.** The Unity view is attached, visible (`windowVis=0`),
  focused, full-size, with a valid Vulkan swapchain (`SetWindow`,
  `InitializeOrResetSwapChain 1080x2340`) by ~2 s — long before the stall.
- **Not async asset loading.** `Loading.AsyncRead` is asleep ~18 s and wakes
  `UnityMain` for only ~5 ms total. The loader is idle, not starved.
- **Not CPU contention.** `UnityMain` is Runnable (waiting for a core) only
  ~99 ms across the entire ~24 s.
- **Not core/frequency throttling.** `UnityMain` runs ~18 s on the big X1 cores
  (CPU 6/7), the fastest on the device.
- **Not vsync / surface / compositor.** The "Made with Unity" splash *animates*
  (presents work), then holds; tapping the screen does **not** wake it (no input
  or vsync is involved).
- **Not the host-app markup.** Reproduces with a single full-screen
  `<UnityView>`, with and without a parent `backgroundColor`, with and without an
  init `postMessage`. (The example app is fast only because its `GeoPoints`
  scene is trivial — it doesn't carry this loop.)

## Root cause & fix (Unity side)
A **blocking poll/retry loop on the main thread**, entered right after
`SendToReact("UnityReady")`, runs ~2,600 iterations without yielding to the
engine — so frames never advance and the first `Main Camera` render is held off
for ~24 s. Because it blocks the main thread, anything the loop waits on that
depends on a **presented frame / `Time.deltaTime` / `WaitForEndOfFrame` / the
host** can't progress, so it spins to its timeout. Standalone it exits in ~2 s,
so the embedded path runs ~12× the iterations (or times out).

Steps:
1. Find the loop that runs immediately after the `UnityReady` send, in the
   Start / post-ready phase (the **mannequin / DesignController / proportions**
   area the existing markers flag). Log its **iteration count** and **exit
   condition** on entry and exit.
2. Likely fixes:
   - Convert the blocking `while` / `Thread.Sleep` loop into a **coroutine that
     `yield`s each iteration**, so the engine renders frames and any
     frame-/time-dependent condition can resolve (usually 1–2 frames).
   - If it's waiting on a message/config from React Native, render the **default
     state immediately** and apply host data when it arrives — don't block with a
     timeout.
3. Verify on a cold boot: the `WATCHDOG` frame 1 → frame 2 gap should fall from
   ~24,000 ms to tens of ms, and `RENDER Main Camera frame 1` should land within
   ~1 s of `UnityReady`.

## React Native bridge status
No change required in `@azesmway/react-native-unity` for this stall — the trace
exonerates it. The bridge improvements already in place (the `onUnityReady`
handshake, null-safe event emit, lifecycle/teardown hardening) remain useful for
stability but are unrelated to this issue.
