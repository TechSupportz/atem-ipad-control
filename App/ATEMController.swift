import ATEMKit
import Foundation
import Observation

@MainActor
@Observable
final class ATEMController {
    static let defaultHost = "192.168.10.240"
    static let savedHostKey = "atemHost"

    private(set) var connectionState: ATEMConnectionState = .disconnected
    private(set) var snapshot = ATEMStateSnapshot()
    private(set) var initialStateCommandCount = 0
    private(set) var errorMessage: String?
    private(set) var shouldStayConnected = false

    var host: String {
        didSet {
            UserDefaults.standard.set(host, forKey: Self.savedHostKey)
        }
    }

    private let connection: ATEMConnection
    private var eventTask: Task<Void, Never>?
    private var foregroundReconnectTask: Task<Void, Never>?

    init(
        host: String = UserDefaults.standard.string(forKey: savedHostKey) ?? defaultHost,
        connection: ATEMConnection = ATEMConnection()
    ) {
        self.host = host
        self.connection = connection
        observeConnection()
    }

    var isConnected: Bool {
        connectionState == .connected
    }

    var isBusy: Bool {
        switch connectionState {
        case .connecting, .synchronizing, .reconnecting:
            return true
        case .disconnected, .connected, .failed:
            return false
        }
    }

    var statusTitle: String {
        switch connectionState {
        case .disconnected:
            return "Disconnected"
        case .connecting:
            return "Connecting"
        case .synchronizing:
            return "Synchronizing"
        case .connected:
            return "Connected"
        case .reconnecting:
            return "Reconnecting"
        case .failed:
            return "Connection failed"
        }
    }

    func connect() {
        shouldStayConnected = true
        errorMessage = nil
        initialStateCommandCount = 0

        do {
            try connection.connect(host: host)
        } catch {
            shouldStayConnected = false
            errorMessage = error.localizedDescription
        }
    }

    func disconnect() {
        foregroundReconnectTask?.cancel()
        shouldStayConnected = false
        errorMessage = nil
        connection.disconnect()
    }

    func updateHost(_ newHost: String) {
        let trimmedHost = newHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedHost != host else {
            return
        }

        disconnect()
        host = trimmedHost
    }

    func resumeAfterForegrounding() {
        guard shouldStayConnected, !isConnected, !isBusy else {
            return
        }

        foregroundReconnectTask?.cancel()
        connection.disconnect()
        foregroundReconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled, let self, self.shouldStayConnected else {
                return
            }
            self.connect()
        }
    }

    private func observeConnection() {
        let events = connection.events
        eventTask = Task { [weak self] in
            for await event in events {
                guard !Task.isCancelled else {
                    return
                }
                self?.handle(event)
            }
        }
    }

    private func handle(_ event: ATEMConnection.Event) {
        switch event {
        case let .connectionStateChanged(state):
            connectionState = state
            if case let .failed(error) = state {
                errorMessage = error.localizedDescription
            }
        case let .stateChanged(snapshot):
            self.snapshot = snapshot
        case .commandReceived:
            if !snapshot.isInitialSyncComplete {
                initialStateCommandCount += 1
            }
        case .initialSyncCompleted:
            errorMessage = nil
        case let .diagnostic(message):
            if message.localizedCaseInsensitiveContains("denied") {
                errorMessage = message
            }
        case .packet:
            break
        }
    }
}
