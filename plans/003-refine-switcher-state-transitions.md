# 003 — Refine switcher state transitions

- **Status**: DONE
- **Commit**: 732f650
- **Severity**: MEDIUM
- **Category**: Cohesion & missed opportunities
- **Estimated scope**: 1 file, about 20 lines

## Problem

The tally source name uses a numeric rolling transition even though source
names are arbitrary strings:

```swift
// App/SwitcherControlView.swift:289 — current
Text(sourceName)
    .font(.headline)
    .foregroundStyle(.primary)
    .contentTransition(.numericText())
```

Meanwhile, the meaningful state surfaces teleport between neutral, Preview
green, Program red, and transition red:

```swift
// App/SwitcherControlView.swift:359 — current
.foregroundStyle(foregroundStyle)
.background(backgroundStyle, in: RoundedRectangle(cornerRadius: 16))
```

The numeric roll is mismatched to the content while the state change that
would benefit from continuity gets none.

## Target

- Remove `.contentTransition(.numericText())` from `TallyStatus`.
- Keep tally text changes immediate; this is a high-frequency controller.
- Animate only source-button background fill and border color for `120ms`.
- Use the same strong ease-out curve as press feedback:
  `Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.12)`.
- Scope animations to the rounded-rectangle fill and stroke shapes so label
  content and layout remain immediate and stationary.
- Animate on both `light` and `isPending` changes.

Use this exact shared token:

```swift
private enum SwitcherMotion {
    static let stateChange = Animation.timingCurve(
        0.23,
        1,
        0.32,
        1,
        duration: 0.12
    )
}
```

## Repo conventions to follow

- Extend the same file-private `SwitcherMotion` enum created by plans 001 and
  002.
- `SourceLight` is already `Equatable`, so it is a valid scoped animation
  value.
- Preserve red Program, green Preview, red transition, and the existing
  non-color PGM/PVW/TAKE labels.

## Steps

1. Add `stateChange` to `SwitcherMotion`.
2. Remove `.contentTransition(.numericText())` from `TallyStatus`.
3. Replace the shorthand source-button `.background(backgroundStyle, in:)`
   with a background closure containing a rounded rectangle filled by
   `backgroundStyle`.
4. On that fill shape only, add
   `.animation(SwitcherMotion.stateChange, value: light)` and the same scoped
   animation for `isPending`.
5. Apply those two scoped animations to the border `RoundedRectangle` only.
6. Do not attach `.animation` to the Button, VStack, text, padding, or frames.

## Boundaries

- Do NOT animate source names, labels, text, layout, or button geometry.
- Do NOT change any colors or state priority.
- Do NOT add animation to connection status, settings, or the error banner.
- Do NOT add dependencies.
- If the cited code has drifted since commit `732f650`, stop and report rather
  than improvising.

## Verification

- **Mechanical**: run `swift test` and build the iPad simulator target.
- **Feel check**:
  - Change Preview rapidly across Inputs 1–4. Background/border color should
    settle quickly with no delayed label or hit target.
  - CUT between two inputs. The old and new PGM/PVW labels must update
    immediately; only the surface color has a brief continuity cue.
  - Trigger AUTO. Both relevant inputs turn red without number rolling,
    scaling, or layout motion.
  - Enable Reduce Motion. Color/opacity feedback may remain because it contains
    no geometric movement.
- **Done when**: only state color eases for 120ms; all text and geometry remain
  crisp.
