# ATEM Mini iPad Controller

This repository currently contains Milestone 1 of the implementation plan: a
small native Swift protocol package and a macOS command-line probe. The SwiftUI
iPad app intentionally has not been created yet. The project must first prove
the session handshake and initial state transfer against the physical original
ATEM Mini.

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

The packet and command formats were checked against
[Sofie ATEM Connection](https://github.com/Sofie-Automation/sofie-atem-connection)
at commit `4af354321d7fdf4be5381c9343f28a50e25c43f1` and compared with
[Swift-Atem](https://github.com/Dev1an/Swift-Atem).

## Build and test

```sh
swift test
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

## Protocol assumptions

- UDP port `9910` is used by the ATEM control protocol.
- The client sends the maintained Sofie handshake shape, replacing its
  initiation ID for each connection. The switcher remains authoritative and
  assigns the session ID returned by the new-session packet.
- Packet counters wrap at `32768`, not `65536`.
- Mix Effect block 0 is the only block used by the original ATEM Mini.
- Physical panel Cut Bus versus Program/Preview mode does not alter network
  state parsing; incoming `PrgI` and `PrvI` messages always win.
