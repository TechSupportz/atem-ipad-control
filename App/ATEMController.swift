import ATEMKit
import Foundation
import Observation

@MainActor
@Observable
final class ATEMController {
    enum TransitionAction: String {
        case cut = "CUT"
        case auto = "AUTO"
    }

    static let defaultHost = "192.168.10.240"
    static let savedHostKey = "atemHost"

    private(set) var connectionState: ATEMConnectionState = .disconnected
    private(set) var snapshot = ATEMStateSnapshot()
    private(set) var initialStateCommandCount = 0
    private(set) var errorMessage: String?
    private(set) var shouldStayConnected = false
    private(set) var pendingProgramInput: UInt16?
    private(set) var pendingPreviewInput: UInt16?
    private(set) var pendingTransition: TransitionAction?
    private(set) var isFadeToBlackPending = false

    var host: String {
        didSet {
            UserDefaults.standard.set(host, forKey: Self.savedHostKey)
        }
    }

    private let connection: ATEMConnection
    private var eventTask: Task<Void, Never>?
    private var foregroundReconnectTask: Task<Void, Never>?
    private var pendingProgramTask: Task<Void, Never>?
    private var pendingPreviewTask: Task<Void, Never>?
    private var pendingTransitionTask: Task<Void, Never>?
    private var fadeToBlackTask: Task<Void, Never>?

    init(
        host: String = UserDefaults.standard.string(forKey: savedHostKey) ?? defaultHost,
        connection: ATEMConnection = ATEMConnection(),
        initialConnectionState: ATEMConnectionState = .disconnected,
        initialSnapshot: ATEMStateSnapshot = ATEMStateSnapshot()
    ) {
        self.host = host
        self.connection = connection
        connectionState = initialConnectionState
        snapshot = initialSnapshot
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
        clearPendingCommands()
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

    func selectProgramInput(_ input: UInt16) {
        guard isConnected,
              (0...4).contains(input),
              snapshot.programInput != input
        else {
            return
        }

        pendingProgramTask?.cancel()
        pendingProgramInput = input
        errorMessage = nil

        do {
            try connection.setProgramInput(input)
            pendingProgramTask = commandTimeoutTask(
                expectedInput: input,
                busName: "Program"
            ) { [weak self] in
                self?.pendingProgramInput = nil
            }
        } catch {
            pendingProgramInput = nil
            errorMessage = error.localizedDescription
        }
    }

    func selectPreviewInput(_ input: UInt16) {
        guard isConnected,
              (0...4).contains(input),
              snapshot.previewInput != input
        else {
            return
        }

        pendingPreviewTask?.cancel()
        pendingPreviewInput = input
        errorMessage = nil

        do {
            try connection.setPreviewInput(input)
            pendingPreviewTask = commandTimeoutTask(
                expectedInput: input,
                busName: "Preview"
            ) { [weak self] in
                self?.pendingPreviewInput = nil
            }
        } catch {
            pendingPreviewInput = nil
            errorMessage = error.localizedDescription
        }
    }

    func performTransition(_ action: TransitionAction) {
        guard isConnected, pendingTransition == nil else {
            return
        }

        pendingTransition = action
        errorMessage = nil

        do {
            switch action {
            case .cut:
                try connection.cut()
            case .auto:
                try connection.autoTransition()
            }

            pendingTransitionTask?.cancel()
            pendingTransitionTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled, let self else {
                    return
                }
                self.pendingTransition = nil
            }
        } catch {
            pendingTransition = nil
            errorMessage = error.localizedDescription
        }
    }

    func performFadeToBlack() {
        guard isConnected,
              !isFadeToBlackPending,
              !snapshot.fadeToBlack.isInTransition
        else {
            return
        }

        isFadeToBlackPending = true
        errorMessage = nil

        do {
            try connection.fadeToBlack()
            fadeToBlackTask?.cancel()
            fadeToBlackTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled, let self else {
                    return
                }
                self.isFadeToBlackPending = false
            }
        } catch {
            isFadeToBlackPending = false
            errorMessage = error.localizedDescription
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
            let previousSnapshot = self.snapshot
            self.snapshot = snapshot
            reconcilePendingCommands(
                from: previousSnapshot,
                to: snapshot
            )
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

    private func reconcilePendingCommands(
        from previousSnapshot: ATEMStateSnapshot,
        to snapshot: ATEMStateSnapshot
    ) {
        if snapshot.programInput == pendingProgramInput {
            pendingProgramTask?.cancel()
            pendingProgramTask = nil
            pendingProgramInput = nil
        }

        if snapshot.previewInput == pendingPreviewInput {
            pendingPreviewTask?.cancel()
            pendingPreviewTask = nil
            pendingPreviewInput = nil
        }

        if pendingTransition != nil,
           snapshot.transition.isInTransition
            || snapshot.programInput != previousSnapshot.programInput
            || snapshot.previewInput != previousSnapshot.previewInput {
            pendingTransitionTask?.cancel()
            pendingTransitionTask = nil
            pendingTransition = nil
        }

        if isFadeToBlackPending,
           snapshot.fadeToBlack != previousSnapshot.fadeToBlack {
            fadeToBlackTask?.cancel()
            fadeToBlackTask = nil
            isFadeToBlackPending = false
        }
    }

    private func commandTimeoutTask(
        expectedInput: UInt16,
        busName: String,
        clearPending: @escaping @MainActor () -> Void
    ) -> Task<Void, Never> {
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, let self else {
                return
            }
            clearPending()
            self.errorMessage = "\(busName) Input \(expectedInput) was not confirmed by the ATEM."
        }
    }

    private func clearPendingCommands() {
        pendingProgramTask?.cancel()
        pendingPreviewTask?.cancel()
        pendingTransitionTask?.cancel()
        fadeToBlackTask?.cancel()
        pendingProgramTask = nil
        pendingPreviewTask = nil
        pendingTransitionTask = nil
        fadeToBlackTask = nil
        pendingProgramInput = nil
        pendingPreviewInput = nil
        pendingTransition = nil
        isFadeToBlackPending = false
    }
}
