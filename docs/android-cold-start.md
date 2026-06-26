# Android cold-start: slow first scene load (~20–30s) — RESOLVED

**Root cause (confirmed): the host app's Android build was compressing Unity's
asset files.** On a cold launch Unity had to decompress them on the CPU before
the first scene could render — that was the entire stall. Fast on iOS and in a
standalone Unity build because neither compresses Unity's assets.

## The fix
Tell the **app module's** Android build not to compress Unity's data files. In
`android/app/build.gradle`:

```groovy
android {
  // AGP 7+ : androidResources { }   |   older AGP : aaptOptions { }
  androidResources {
    noCompress += ['.unity3d', '.ress', '.resource', '.obb', '.bundle']
  }
}
```

> The `unityStreamingAssets=.unity3d` line in `gradle.properties` (README setup
> step 3) only applies to the **`unityLibrary`** module. The final APK is
> packaged by the **app** module, which re-compresses Unity's assets unless you
> add the `noCompress` block above. Setting it only in `unityLibrary` is not
> enough.

## Symptom
| Scenario | First scene |
| --- | --- |
| Cold first launch, embedded (assets compressed) | ~20–34s |
| Standalone Unity Android build | ~2–3s |
| iOS (embedded) | fast |

## Why it matched the Perfetto trace exactly
The trace showed the cost was CPU-bound on Unity's main thread, and that is
precisely what zlib decompression looks like:

- `UnityMain` ran ~21s of pure CPU on the **big (X1) cores** → inflating
  compressed assets (decompression is CPU-bound, not I/O-bound).
- The async loader thread (`Loading.AsyncRead`) was mostly **idle** → the raw
  disk read was cheap; the expensive part was the **decompress on the consumer
  thread (`UnityMain`)**, which is why the loader looked idle and (earlier)
  threw the investigation off the asset-loading scent.
- `UnityMain` was Runnable only ~99ms and stayed on the prime cores → not
  contention, not scheduling; genuinely doing work.
- The ~2,600 "work + short sleep" iterations were read-a-block / inflate-a-block
  cycles, not a logic poll loop (the earlier "blocking startup loop" reading of
  this doc was an inference and was **wrong** — kept here only as a correction).

## Why it was Android-embedded-only
- **Standalone Android:** Unity's own exported build marks these extensions
  `noCompress`, so the data is stored uncompressed and memory-mapped → no inflate.
- **iOS:** the app bundle doesn't deflate Unity's data the way an Android APK
  does → no inflate.
- **Embedded Android:** the host RN app's APK packaging re-compressed Unity's
  data (the app module didn't carry Unity's `noCompress` list) → Unity had to
  inflate every asset on the CPU at startup.

## React Native bridge status
Not a bridge bug — it's host-app Android packaging. No runtime change to
`@azesmway/react-native-unity` was required. The README "Known issues" section
now documents the `noCompress` requirement so future integrations set it up
front.
