# Technical notes

Implementation detail, hardware verification procedure, and protocol
assumptions for the ATEM Mini iPad Controller. For what the project is and how
to run it, see [README.md](README.md).

## Milestone 1 verification

Verified on 26 July 2026 against an original ATEM Mini at
`192.168.18.240`:

- The ATEM echoed the client initiation ID, then assigned session `32784`.
- The complete initial state transfer reached `InCm` successfully.
- Initial Program and Preview were both Input 1.
- The connection remained live for more than 90 seconds.
- Pressing physical Input 2 produced an authoritative `PrvI` update to
  Preview 2 while Program remained Input 1.
- Preview Input 4, CUT, and AUTO were subsequently exercised from the probe;
  the physical panel and authoritative ATEM state updates agreed each time.

The captured ground-truth packet log is stored under `Diagnostics/`.

## What is implemented

- `ATEMKit`, a dependency-free Swift package using `Network.framework`
- Direct UDP connection to port `9910`
- Session handshake and fresh client initiation ID
- 15-bit packet sequencing and cumulative acknowledgements
- Retransmit requests, timed retransmission, and bounded retry handling
- Idle keepalive packets and five-second liveness detection
- Safe parsing of framed ATEM commands
- Initial state dump capture through the `InCm` marker
- Authoritative Program (`PrgI`) and Preview (`PrvI`) state parsing
- Typed Program, Preview, Cut, and Auto command encoding
- `atem-probe`, a macOS executable for physical-switcher verification
- A landscape iPad app target linked to the local `ATEMKit` package
- Persisted switcher IP configuration and connect/disconnect controls
- Local Network usage description and explicit permission-denied messaging
- Foreground reconnect and screen-awake behavior while connected
- A handshake diagnostics surface showing Program, Preview, command count,
  and initial-sync completion
- A single combined source bus matching the ATEM Program/Preview panel:
  Inputs 1–4 stage Preview, red identifies Program, and green identifies Preview
- Physically verified CUT and AUTO controls
- Immediate pending feedback that reconciles against authoritative ATEM state

The packet and command formats were checked against
[Sofie ATEM Connection](https://github.com/Sofie-Automation/sofie-atem-connection)
at commit `4af354321d7fdf4be5381c9343f28a50e25c43f1` and compared with
[Swift-Atem](https://github.com/Dev1an/Swift-Atem).

## Build and test

```sh
swift test
```

```sh
swift build --product atem-probe
```

## Physical ATEM verification

1. Connect the Mac to the same Nokia Beacon network as the ATEM Mini.
2. Confirm the ATEM address in ATEM Setup. The default below is
   `192.168.10.240`.
3. Quit ATEM Software Control for the first test so another client cannot
   obscure a connection-slot issue.
4. Run:

   ```sh
   swift run atem-probe --host 192.168.10.240
   ```

5. Wait for `Initial state synchronization complete`.
6. Leave the probe running for at least 30 seconds. It should remain connected
   and continue to report keepalive acknowledgements without a reconnect.
7. Press Input 1–4 on the hardware panel. The probe should print Program or
   Preview changes that match the switcher's actual state.
8. Stop with Control-C.

The probe saves the complete inbound initial-state datagrams to a timestamped
`atem-state-dump-*.log` file in the current directory. Keep that file: it is the
ground truth for later parsing work. A custom location can be supplied with
`--dump /absolute/path/to/file.log`.

If the probe times out, rerun it with the ATEM powered on and ATEM Software
Control closed, then share the complete console output and generated dump (if
one exists) before proceeding to the iPad app.

## Physical iPad verification

1. Open `ATEMController.xcodeproj` in Xcode.
2. Select the **ATEM Controller** scheme and a connected iPad.
3. Choose a Development Team under **Signing & Capabilities**, then run.
4. Open Settings in the app and set the address to `192.168.18.240`.
5. Tap **Connect** and allow Local Network access when prompted.
6. Confirm the status reaches **Connected**, initial sync reads **Complete**,
   and the displayed Program/Preview inputs match the ATEM panel.
7. Leave the Beacon WAN disconnected throughout the test.

For the denial path, delete the app from the iPad, reinstall it, tap Connect,
and deny Local Network access. The app should stop retrying and display a
message directing you to enable access in Settings. Re-enable access in the
iPad Settings app, foreground ATEM Controller, and connect again.

## Protocol assumptions

- UDP port `9910` is used by the ATEM control protocol.
- The client sends the maintained Sofie handshake shape, replacing its
  initiation ID for each connection. The handshake response echoes that ID;
  the switcher remains authoritative and supplies the assigned session ID on
  the first sequenced state packet.
- Packet counters wrap at `32768`, not `65536`.
- Mix Effect block 0 is the only block used by the original ATEM Mini.
- Physical panel Cut Bus versus Program/Preview mode does not alter network
  state parsing; incoming `PrgI` and `PrvI` messages always win.
