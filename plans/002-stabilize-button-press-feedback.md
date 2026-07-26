# 002 — Stabilize button press feedback

- **Status**: DONE
- **Commit**: 732f650
- **Severity**: HIGH
- **Category**: Purpose & frequency
- **Estimated scope**: 1 file, about 25 lines

## Problem

Every source and transition button scales its entire label tree on touch:

```swift
// App/SwitcherControlView.swift:495 — current
configuration.label
    .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
    .brightness(configuration.isPressed ? -0.05 : 0)
    .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
```

For CUT, AUTO, and FTB, pending state also inserts a spinner before the text:

```swift
// App/SwitcherControlView.swift:442 — current
HStack(spacing: 10) {
    if isPending {
        ProgressView()
            .tint(foreground)
    }

    VStack(alignment: .leading, spacing: 1) {
        Text(title)
        Text(detail)
    }
}
```

The scale makes the text visibly bounce on a high-frequency live control, and
the conditional spinner changes HStack geometry so the label jumps sideways.

## Target

Press feedback must be crisp and non-geometric:

- Remove scale and brightness from `PanelButtonStyle`.
- Use opacity-only press feedback: `1` normally and `0.82` while pressed.
- Animate it for `120ms` with the strong ease-out curve from the audit:
  `Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.12)`.
- Reserve a stable `20×20` trailing slot for the pending spinner at all times.
- Fade the spinner in/out within that slot; never insert content before the
  title.
- Do not animate or move the title/detail stack.

Use this exact motion token:

```swift
private enum SwitcherMotion {
    static let press = Animation.timingCurve(
        0.23,
        1,
        0.32,
        1,
        duration: 0.12
    )
}
```

## Repo conventions to follow

- Keep the shared `PanelButtonStyle` so source and transition controls retain
  consistent press feedback.
- Keep the existing giant button frames and labels.
- Keep all motion local to `App/SwitcherControlView.swift`.

## Steps

1. Add the exact `press` token to the file-private `SwitcherMotion` enum used
   by plan 001.
2. In `PanelButtonStyle`, remove
   `@Environment(\.accessibilityReduceMotion)`, `.scaleEffect`, and
   `.brightness`.
3. Apply `.opacity(configuration.isPressed ? 0.82 : 1)` and
   `.animation(SwitcherMotion.press, value: configuration.isPressed)`.
4. In `ControlButton`, keep the title/detail VStack at the leading edge.
5. Move pending UI after the `Spacer` into a `ZStack` with a fixed
   `.frame(width: 20, height: 20)`. Always render the slot. The
   `ProgressView` may be conditional inside the ZStack because its container
   size remains stable.
6. Give the spinner `.transition(.opacity)` and scope
   `.animation(SwitcherMotion.press, value: isPending)` to its fixed ZStack
   only.

## Boundaries

- Do NOT change button sizes, layout grouping, labels, commands, or enabled
  rules.
- Do NOT use springs or bounce.
- Do NOT animate padding, width, height, or position.
- Do NOT add haptics or dependencies.
- If the cited code has drifted since commit `732f650`, stop and report rather
  than improvising.

## Verification

- **Mechanical**: run `swift test`, then build and launch on an iPad simulator.
- **Feel check**:
  - Slow interactions to 10% in Xcode/Simulator if available.
  - Press CUT repeatedly. The surface may dim, but neither line of text may
    scale, bounce, or move.
  - Toggle CUT/AUTO pending state. The spinner fades in the trailing slot and
    the title remains at the exact same coordinates.
  - Press source buttons and confirm the same subtle opacity feedback.
- **Done when**: all labels remain stationary throughout touch-down, release,
  and pending-state changes.
