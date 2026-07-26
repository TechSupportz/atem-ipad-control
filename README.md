# ATEM Mini iPad Controller

An iPad app for controlling a Blackmagic ATEM Mini over Wi-Fi.

The ATEM Mini is a small live-production video switcher. This app connects to
one over the local network and mirrors its live-switching controls: you enter
the switcher's IP address, connect, and the app shows which source is on
Program, which is staged on Preview, and gives you buttons to change either.

## Controls

- **Program and Preview state.** Program is red, Preview is green, matching the
  hardware panel. State comes from the switcher, so presses on the physical
  panel show up in the app too.
- **Sources.** Inputs 1–4 stage a source on Preview.
- **CUT and AUTO.** Instant switch, or a timed transition.
- **FTB.** Fade to black, blinking while program output is black.

Taps show pending feedback immediately, then reconcile against the state the
ATEM reports.

## Behaviour

- Landscape layout, large touch targets.
- Screen stays awake while connected.
- Reconnects when the app returns to the foreground.
- Reports connection loss, and separately reports when iPadOS has denied Local
  Network access.
- No haptics. iPad does not have the iPhone haptic engine, so feedback is
  visual.

## Scope

Live switching only. No keyers, audio mixing, macros, media player, or
streaming controls.

Supported hardware is the original ATEM Mini: four HDMI inputs, one Mix Effect
block. Other ATEM models are not a target.

The networking does not use the Blackmagic SDK. It is a clean-room
implementation of the ATEM control protocol on `Network.framework`, verified
against physical hardware.

## Getting started

Requires a Mac with Xcode, an iPad, and an ATEM Mini on the same network.

1. Open `ATEMController.xcodeproj` in Xcode.
2. Select the **ATEM Controller** scheme and your connected iPad.
3. Choose a Development Team under **Signing & Capabilities**, then run.
4. In the app, open Settings and enter the switcher's IP address. ATEM Setup
   will tell you what it is.
5. Tap **Connect** and allow Local Network access when iPadOS asks.

The address persists between launches.

## Repository layout

| Path | What it holds |
| --- | --- |
| `App/` | The SwiftUI iPad app |
| `Sources/ATEMKit/` | The ATEM protocol client |
| `Sources/ATEMProbe/` | `atem-probe`, a macOS CLI for testing against hardware |
| `Diagnostics/` | Captured ground-truth packet logs |
| `plans/` | Design notes for in-progress work |
| `teaching/` | Learning material on the protocol and this codebase |

## Further reading

[TECHNICAL.md](TECHNICAL.md) covers the protocol implementation, hardware
verification procedures, and the assumptions the client relies on.
