# 001 — Restore the FTB warning pulse

- **Status**: DONE
- **Commit**: 732f650
- **Severity**: HIGH
- **Category**: Interruptibility
- **Estimated scope**: 1 file, about 30 lines

## Problem

The fully-black warning no longer visibly blinks. The continuous
`phaseAnimator` is created with a single idle phase and later receives a
different phase array. That runtime phase-list change does not reliably start
the loop:

```swift
// App/SwitcherControlView.swift:480 — current
.phaseAnimator(blinkPhases) { content, opacity in
    content.opacity(opacity)
} animation: { _ in
    .easeInOut(duration: 0.38)
}

private var blinkPhases: [Double] {
    blinks && !reduceMotion ? [1, 0.35] : [1]
}
```

This is safety-critical state feedback: when the ATEM reports
`fadeToBlack.isFullyBlack`, the red FTB surface must keep pulsing until that
state clears.

## Target

Replace the dynamic phase list with a cancellable `.task(id:)` driven by the
single Boolean `blinks && !reduceMotion`.

- Store a local background opacity beginning at `1`.
- When blinking is enabled, alternate the stored value between `1` and `0.35`.
- Animate each opacity leg linearly for `180ms`.
- Wait `360ms` between each state change, producing a clear warning cadence
  without a soft bounce.
- Pulse only the button's background fill; keep its `FTB` and `Active` text at
  full opacity and geometrically stationary.
- When blinking stops, the task is cancelled and opacity returns immediately
  to `1`.
- With Reduce Motion enabled, keep the FTB surface steady red at opacity `1`.

Use this exact motion definition:

```swift
private enum SwitcherMotion {
    static let warningPulse = Animation.linear(duration: 0.18)
    static let warningPulseInterval = Duration.milliseconds(360)
    static let warningDimOpacity = 0.35
}
```

## Repo conventions to follow

- Motion remains SwiftUI-native and local to
  `App/SwitcherControlView.swift`; do not add a dependency.
- The existing component already reads
  `@Environment(\.accessibilityReduceMotion)`.
- The former implementation used `.task(id:)` and cancellation-aware
  `Task.sleep`; preserve that lifecycle pattern.

## Steps

1. In `App/SwitcherControlView.swift`, add `SwitcherMotion` as a file-private
   enum near the other file-private UI types.
2. Add `@State private var warningBackgroundOpacity = 1.0` to
   `ControlButton`.
3. Remove `phaseAnimator`, `blinkPhases`, and any animation that wraps the
   entire `Button`.
4. Change the rounded-rectangle background fill from `background` to
   `background.opacity(warningBackgroundOpacity)`. Do not apply this opacity to
   the label.
5. Add `.task(id: blinks && !reduceMotion)`. Reset opacity to `1`, exit when
   false, otherwise loop: animate to `0.35`, sleep `360ms`, animate to `1`,
   sleep `360ms`. Exit immediately when cancellation throws.

## Boundaries

- Do NOT change ATEM protocol or controller state.
- Do NOT blink while fade-to-black is merely pending or transitioning;
  `blinks` remains tied only to `isFullyBlack`.
- Do NOT animate the text, layout, frame, scale, or button hit target.
- Do NOT add dependencies.
- If the cited code has drifted since commit `732f650`, stop and report rather
  than improvising.

## Verification

- **Mechanical**: run `swift test`, then build the `ATEM Controller` scheme for
  an iPad simulator; both must succeed.
- **Feel check**:
  - Render or inject a state with `fadeToBlack.isFullyBlack == true`.
  - Confirm the red background repeatedly pulses while `FTB` and `Active`
    remain stationary and fully legible.
  - Clear the state mid-pulse and confirm the background immediately settles
    at full opacity.
  - Enable Reduce Motion and confirm the active button remains steady red.
- **Done when**: fully black always produces a continuous visible background
  pulse, clearing the state stops it, and no label moves.
