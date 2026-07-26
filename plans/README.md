# Animation refinement plans

| Plan | Title | Severity | Status |
|---|---|---:|---|
| 001 | Restore the FTB warning pulse | HIGH | DONE |
| 002 | Stabilize button press feedback | HIGH | DONE |
| 003 | Refine switcher state transitions | MEDIUM | DONE |

## Recommended execution order

1. `001-restore-ftb-warning-pulse.md`
2. `002-stabilize-button-press-feedback.md`
3. `003-refine-switcher-state-transitions.md`

All plans touch `App/SwitcherControlView.swift` and share a file-private
`SwitcherMotion` token enum. Execute them in order so each later plan extends
the token enum rather than creating a duplicate.

No plan changes networking, ATEM commands, controller state, button sizing, or
the giant live-control layout.
