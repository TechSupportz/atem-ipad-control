import ATEMKit
import Foundation

#if canImport(Darwin)
import Darwin
#endif

private struct Options {
    var host = "192.168.10.240"
    var port: UInt16 = 9910
    var timeout: TimeInterval = 15
    var dumpPath: String?
    var automaticallyReconnects = true
    var previewInputToSet: UInt16?

    static func parse(_ arguments: [String]) throws -> Options {
        var options = Options()
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--host":
                index += 1
                guard index < arguments.count else {
                    throw UsageError("Missing value after --host.")
                }
                options.host = arguments[index]
            case "--port":
                index += 1
                guard index < arguments.count,
                      let port = UInt16(arguments[index])
                else {
                    throw UsageError("--port requires a number from 1 to 65535.")
                }
                options.port = port
            case "--timeout":
                index += 1
                guard index < arguments.count,
                      let timeout = TimeInterval(arguments[index]),
                      timeout > 0
                else {
                    throw UsageError("--timeout requires a positive number of seconds.")
                }
                options.timeout = timeout
            case "--dump":
                index += 1
                guard index < arguments.count else {
                    throw UsageError("Missing path after --dump.")
                }
                options.dumpPath = arguments[index]
            case "--no-reconnect":
                options.automaticallyReconnects = false
            case "--set-preview":
                index += 1
                guard index < arguments.count,
                      let input = UInt16(arguments[index]),
                      (1...4).contains(input)
                else {
                    throw UsageError("--set-preview requires an input from 1 to 4.")
                }
                options.previewInputToSet = input
            case "--help", "-h":
                printUsage()
                exit(EXIT_SUCCESS)
            default:
                throw UsageError("Unknown argument: \(argument)")
            }
            index += 1
        }

        return options
    }

    private static func printUsage() {
        print("""
        Usage: atem-probe [options]

          --host <IPv4>       ATEM address (default: 192.168.10.240)
          --port <number>     UDP port (default: 9910)
          --timeout <seconds> Initial synchronization deadline (default: 15)
          --dump <path>       Initial-state dump output path
          --no-reconnect      Stop instead of reconnecting after connection loss
          --set-preview <1-4> Stage one Preview input after synchronization
          --help              Show this help
        """)
    }
}

private struct UsageError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? {
        message
    }
}

private final class InitialStateDump: @unchecked Sendable {
    private let lock = NSLock()
    private var receivedPackets: [Data] = []
    private var isComplete = false

    func append(_ packet: Data) {
        lock.lock()
        defer { lock.unlock() }
        guard !isComplete else {
            return
        }
        receivedPackets.append(packet)
    }

    func finishAndWrite(to path: String) throws {
        lock.lock()
        defer { lock.unlock() }
        guard !isComplete else {
            return
        }
        isComplete = true

        let contents = receivedPackets.enumerated().map { index, packet in
            String(format: "%04d RECV %@", index + 1, packet.hexDump)
        }.joined(separator: "\n") + "\n"

        try contents.write(toFile: path, atomically: true, encoding: .utf8)
    }
}

private actor SynchronizationFlag {
    private(set) var isComplete = false
    private var didSendRequestedCommand = false

    func markComplete() {
        isComplete = true
    }

    func claimRequestedCommand() -> Bool {
        guard !didSendRequestedCommand else {
            return false
        }
        didSendRequestedCommand = true
        return true
    }
}

private extension Data {
    var hexDump: String {
        map { String(format: "%02x", $0) }.joined()
    }
}

private func defaultDumpPath() -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("atem-state-dump-\(formatter.string(from: Date())).log")
        .path
}

private func timestamp() -> String {
    ISO8601DateFormatter().string(from: Date())
}

@main
private enum ATEMProbe {
    static func main() async {
        do {
            let options = try Options.parse(Array(CommandLine.arguments.dropFirst()))
            let dumpPath = options.dumpPath ?? defaultDumpPath()
            let dump = InitialStateDump()
            let synchronization = SynchronizationFlag()
            let connection = ATEMConnection(
                configuration: .init(
                    automaticallyReconnects: options.automaticallyReconnects,
                    emitsPacketEvents: true
                )
            )

            print("[\(timestamp())] Connecting to \(options.host):\(options.port)…")
            print("[\(timestamp())] Initial state dump will be saved to \(dumpPath)")

            try connection.connect(host: options.host, port: options.port)

            let signalStream = interruptSignalStream()
            await withTaskGroup(of: String?.self) { group in
                group.addTask {
                    for await event in connection.events {
                        switch event {
                        case let .connectionStateChanged(state):
                            print("[\(timestamp())] State: \(describe(state))")

                        case let .stateChanged(snapshot):
                            if let program = snapshot.programInput {
                                print("[\(timestamp())] Program input: \(program)")
                            }
                            if let preview = snapshot.previewInput {
                                print("[\(timestamp())] Preview input: \(preview)")
                            }

                        case let .commandReceived(command):
                            print(
                                "[\(timestamp())] Command \(command.name) (\(command.body.count) body bytes)"
                            )

                        case let .packet(direction, packet):
                            if direction == .received {
                                dump.append(packet)
                                print(
                                    "[\(timestamp())] \(direction.rawValue) \(packet.count) bytes"
                                )
                            } else {
                                print(
                                    "[\(timestamp())] \(direction.rawValue) \(packet.hexDump)"
                                )
                            }

                        case let .diagnostic(message):
                            print("[\(timestamp())] Diagnostic: \(message)")

                        case .initialSyncCompleted:
                            await synchronization.markComplete()
                            do {
                                try dump.finishAndWrite(to: dumpPath)
                                print("[\(timestamp())] Initial state synchronization complete.")
                                print("[\(timestamp())] Saved complete initial state dump to \(dumpPath)")
                                print("[\(timestamp())] Leave this running for 30 seconds, then operate the hardware panel.")
                            } catch {
                                print("[\(timestamp())] Could not save state dump: \(error.localizedDescription)")
                            }
                            if let input = options.previewInputToSet,
                               await synchronization.claimRequestedCommand() {
                                do {
                                    try connection.setPreviewInput(input)
                                    print(
                                        "[\(timestamp())] Requested Preview input \(input); awaiting authoritative PrvI response."
                                    )
                                } catch {
                                    print(
                                        "[\(timestamp())] Could not request Preview input \(input): \(error.localizedDescription)"
                                    )
                                }
                            }
                        }
                    }
                    return nil
                }

                group.addTask {
                    for await _ in signalStream {
                        return "Interrupted."
                    }
                    return nil
                }

                group.addTask {
                    do {
                        try await Task.sleep(for: .seconds(options.timeout))
                        if await synchronization.isComplete {
                            // Initial sync met its deadline. Keep this child alive
                            // until the signal task ends the probe.
                            while !Task.isCancelled {
                                try await Task.sleep(for: .seconds(60))
                            }
                            return nil
                        }
                        return "Initial synchronization did not complete within \(options.timeout) seconds."
                    } catch {
                        return nil
                    }
                }

                if let reason = await group.next() ?? nil {
                    print("[\(timestamp())] \(reason)")
                }
                group.cancelAll()
            }

            connection.disconnect()
        } catch {
            fputs("atem-probe: \(error.localizedDescription)\n", stderr)
            fputs("Run atem-probe --help for usage.\n", stderr)
            exit(EXIT_FAILURE)
        }
    }

    private static func describe(_ state: ATEMConnectionState) -> String {
        switch state {
        case .disconnected:
            return "disconnected"
        case .connecting:
            return "connecting"
        case .synchronizing:
            return "synchronizing"
        case .connected:
            return "connected"
        case .reconnecting:
            return "reconnecting"
        case let .failed(error):
            return "failed — \(error.localizedDescription)"
        }
    }

    private static func interruptSignalStream() -> AsyncStream<Void> {
        #if canImport(Darwin)
        signal(SIGINT, SIG_IGN)
        return AsyncStream { continuation in
            let source = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
            source.setEventHandler {
                continuation.yield()
                continuation.finish()
            }
            continuation.onTermination = { _ in
                source.cancel()
            }
            source.resume()
        }
        #else
        return AsyncStream { _ in }
        #endif
    }
}
