import Foundation
import Network

public final class ATEMConnection: @unchecked Sendable {
    public struct Configuration: Sendable {
        public var keepaliveInterval: TimeInterval
        public var connectionTimeout: TimeInterval
        public var reconnectDelay: TimeInterval
        public var retransmitTimeout: TimeInterval
        public var maximumPacketRetries: Int
        public var automaticallyReconnects: Bool
        public var emitsPacketEvents: Bool

        public init(
            keepaliveInterval: TimeInterval = 1,
            connectionTimeout: TimeInterval = 5,
            reconnectDelay: TimeInterval = 1,
            retransmitTimeout: TimeInterval = 0.06,
            maximumPacketRetries: Int = 10,
            automaticallyReconnects: Bool = true,
            emitsPacketEvents: Bool = false
        ) {
            self.keepaliveInterval = keepaliveInterval
            self.connectionTimeout = connectionTimeout
            self.reconnectDelay = reconnectDelay
            self.retransmitTimeout = retransmitTimeout
            self.maximumPacketRetries = maximumPacketRetries
            self.automaticallyReconnects = automaticallyReconnects
            self.emitsPacketEvents = emitsPacketEvents
        }
    }

    public enum Event: Sendable {
        case connectionStateChanged(ATEMConnectionState)
        case stateChanged(ATEMStateSnapshot)
        case commandReceived(ATEMRawCommand)
        case packet(ATEMPacketDirection, Data)
        case diagnostic(String)
        case initialSyncCompleted
    }

    private enum InternalState {
        case stopped
        case waitingForNetwork
        case waitingForHandshake
        case established
    }

    private struct InFlightPacket {
        let packetID: UInt16
        let data: Data
        var lastSentAt: ContinuousClock.Instant
        var retryCount: Int
    }

    public let events: AsyncStream<Event>

    public var stateSnapshot: ATEMStateSnapshot {
        queue.sync { snapshotStorage }
    }

    public var connectionState: ATEMConnectionState {
        queue.sync { connectionStateStorage }
    }

    private let configuration: Configuration
    private let queue = DispatchQueue(label: "ATEMKit.connection")
    private let clock = ContinuousClock()
    private let continuation: AsyncStream<Event>.Continuation

    private var host = ""
    private var port: UInt16 = ATEMProtocol.port
    private var networkConnection: NWConnection?
    private var timer: DispatchSourceTimer?
    private var reconnectWorkItem: DispatchWorkItem?
    private var internalState = InternalState.stopped
    private var explicitlyDisconnected = true

    private var initiationID: UInt16 = 0
    private var sessionID: UInt16 = 0
    private var nextSendPacketID: UInt16 = 1
    private var lastReceivedPacketID: UInt16 = 0
    private var lastReceivedAt: ContinuousClock.Instant?
    private var lastSentAt: ContinuousClock.Instant?
    private var inFlightPackets: [InFlightPacket] = []

    private var snapshotStorage = ATEMStateSnapshot()
    private var connectionStateStorage = ATEMConnectionState.disconnected

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
        let stream = AsyncStream<Event>.makeStream()
        events = stream.stream
        continuation = stream.continuation
    }

    deinit {
        continuation.finish()
        networkConnection?.cancel()
        timer?.cancel()
        reconnectWorkItem?.cancel()
    }

    public func connect(host: String, port: UInt16 = 9910) throws {
        guard Self.isValidIPv4Address(host) else {
            throw ATEMConnectionError.invalidHost(host)
        }

        queue.async { [weak self] in
            guard let self else {
                return
            }

            self.host = host
            self.port = port
            self.explicitlyDisconnected = false

            guard self.internalState == .stopped else {
                self.emit(.diagnostic("Ignored overlapping connection attempt."))
                return
            }

            self.beginConnection(isReconnect: false)
        }
    }

    public func disconnect() {
        queue.async { [weak self] in
            guard let self else {
                return
            }

            self.explicitlyDisconnected = true
            self.stopTransport()
            self.setConnectionState(.disconnected)
        }
    }

    public func setProgramInput(_ source: UInt16) throws {
        try sendCommand(
            ATEMProtocol.busCommand(
                name: ATEMProtocol.CommandName.setProgramInput,
                source: source
            )
        )
    }

    public func setPreviewInput(_ source: UInt16) throws {
        try sendCommand(
            ATEMProtocol.busCommand(
                name: ATEMProtocol.CommandName.setPreviewInput,
                source: source
            )
        )
    }

    public func cut() throws {
        try sendCommand(
            ATEMProtocol.transitionCommand(name: ATEMProtocol.CommandName.cut)
        )
    }

    public func autoTransition() throws {
        try sendCommand(
            ATEMProtocol.transitionCommand(
                name: ATEMProtocol.CommandName.autoTransition
            )
        )
    }

    private static func isValidIPv4Address(_ host: String) -> Bool {
        let components = host.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 4 else {
            return false
        }

        return components.allSatisfy { component in
            guard !component.isEmpty,
                  component.allSatisfy(\.isNumber),
                  let value = UInt8(component)
            else {
                return false
            }
            return String(value) == component || component == "0"
        }
    }

    private func beginConnection(isReconnect: Bool) {
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
        resetSession()

        initiationID = ATEMProtocol.freshInitiationID()
        internalState = .waitingForNetwork
        setConnectionState(isReconnect ? .reconnecting : .connecting)

        guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
            handleFailure(.networkUnavailable("invalid UDP port \(port)"))
            return
        }

        let connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: endpointPort,
            using: .udp
        )
        networkConnection = connection

        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, connection === self.networkConnection else {
                return
            }
            self.handleNetworkState(state)
        }

        startReceiveLoop(connection)
        connection.start(queue: queue)
        startTimer()
    }

    private func handleNetworkState(_ state: NWConnection.State) {
        switch state {
        case .ready:
            internalState = .waitingForHandshake
            let hello = ATEMProtocol.connectHello(initiationID: initiationID)
            sendRaw(hello)
        case let .waiting(error):
            emit(.diagnostic("Network waiting: \(error.localizedDescription)"))
        case let .failed(error):
            handleFailure(.networkUnavailable(error.localizedDescription))
        case .cancelled:
            if !explicitlyDisconnected, internalState != .stopped {
                handleFailure(.disconnected)
            }
        case .setup, .preparing:
            break
        @unknown default:
            emit(.diagnostic("Network entered an unknown state."))
        }
    }

    private func startReceiveLoop(_ connection: NWConnection) {
        connection.receiveMessage { [weak self, weak connection] data, _, _, error in
            guard let self,
                  let connection,
                  connection === self.networkConnection
            else {
                return
            }

            if let data, !data.isEmpty {
                self.receive(data)
            }

            if let error {
                self.handleFailure(.networkUnavailable(error.localizedDescription))
                return
            }

            if self.internalState != .stopped {
                self.startReceiveLoop(connection)
            }
        }
    }

    private func receive(_ data: Data) {
        if configuration.emitsPacketEvents {
            emit(.packet(.received, data))
        }

        do {
            let header = try ATEMPacketHeader.parse(data)
            lastReceivedAt = clock.now

            if header.contains(ATEMProtocol.newSessionID) {
                sessionID = header.sessionID
                lastReceivedPacketID = header.packetID
                internalState = .established
                setConnectionState(.synchronizing)
                sendAcknowledgement(for: header.packetID)
                return
            }

            guard internalState == .established else {
                emit(.diagnostic("Ignored non-handshake packet before session establishment."))
                return
            }

            if header.sessionID != sessionID {
                emit(.diagnostic(
                    "Ignored packet for session \(header.sessionID); active session is \(sessionID)."
                ))
                return
            }

            if header.contains(ATEMProtocol.retransmitRequest) {
                retransmit(from: header.retransmitFromID)
            }

            if header.contains(ATEMProtocol.ackReply) {
                acknowledgeOutboundPackets(through: header.acknowledgementID)
            }

            if header.contains(ATEMProtocol.ackRequest) {
                processSequencedPacket(data, header: header)
            }
        } catch let error as ATEMConnectionError {
            emit(.diagnostic(error.localizedDescription))
        } catch {
            emit(.diagnostic("Unexpected packet parsing error: \(error.localizedDescription)"))
        }
    }

    private func processSequencedPacket(_ data: Data, header: ATEMPacketHeader) {
        let expected = increment(lastReceivedPacketID)

        if header.packetID == expected {
            lastReceivedPacketID = header.packetID
            sendAcknowledgement(for: header.packetID)

            guard data.count > ATEMProtocol.headerLength else {
                return
            }

            do {
                let commands = try ATEMCommandParser.parse(
                    data.subdata(in: ATEMProtocol.headerLength..<data.count)
                )
                for command in commands {
                    apply(command)
                    emit(.commandReceived(command))
                }
            } catch let error as ATEMConnectionError {
                emit(.diagnostic(error.localizedDescription))
            } catch {
                emit(.diagnostic("Unexpected command parsing error: \(error.localizedDescription)"))
            }
        } else if isCoveredByAcknowledgement(
            acknowledgementID: lastReceivedPacketID,
            packetID: header.packetID
        ) {
            // Duplicate retransmission. Never apply its state twice.
            sendAcknowledgement(for: lastReceivedPacketID)
        } else {
            emit(.diagnostic(
                "Missing inbound packet \(expected); received \(header.packetID)."
            ))
            sendRetransmitRequest(from: expected)
        }
    }

    private func apply(_ command: ATEMRawCommand) {
        switch command.name {
        case ATEMProtocol.CommandName.programInput:
            guard command.body.count >= 4,
                  command.body.first == 0,
                  let source = command.body.uint16BE(at: 2)
            else {
                return
            }
            if snapshotStorage.programInput != source {
                snapshotStorage.programInput = source
                emit(.stateChanged(snapshotStorage))
            }

        case ATEMProtocol.CommandName.previewInput:
            guard command.body.count >= 4,
                  command.body.first == 0,
                  let source = command.body.uint16BE(at: 2)
            else {
                return
            }
            if snapshotStorage.previewInput != source {
                snapshotStorage.previewInput = source
                emit(.stateChanged(snapshotStorage))
            }

        case ATEMProtocol.CommandName.initialSyncComplete:
            guard !snapshotStorage.isInitialSyncComplete else {
                return
            }
            snapshotStorage.isInitialSyncComplete = true
            setConnectionState(.connected)
            emit(.stateChanged(snapshotStorage))
            emit(.initialSyncCompleted)

        default:
            break
        }
    }

    private func sendCommand(_ payload: Data) throws {
        let isEstablished = queue.sync {
            internalState == .established
                && snapshotStorage.isInitialSyncComplete
        }
        guard isEstablished else {
            throw ATEMConnectionError.disconnected
        }

        queue.async { [weak self] in
            self?.sendSequenced(payload: payload)
        }
    }

    private func sendSequenced(payload: Data = Data()) {
        let packetID = nextSendPacketID
        nextSendPacketID = increment(nextSendPacketID)

        let packet = ATEMProtocol.packet(
            flags: ATEMProtocol.ackRequest,
            sessionID: sessionID,
            packetID: packetID,
            payload: payload
        )
        let now = clock.now
        inFlightPackets.append(
            InFlightPacket(
                packetID: packetID,
                data: packet,
                lastSentAt: now,
                retryCount: 0
            )
        )
        sendRaw(packet)
    }

    private func sendAcknowledgement(for packetID: UInt16) {
        sendRaw(
            ATEMProtocol.packet(
                flags: ATEMProtocol.ackReply,
                sessionID: sessionID,
                acknowledgementID: packetID
            )
        )
    }

    private func sendRetransmitRequest(from packetID: UInt16) {
        sendRaw(
            ATEMProtocol.packet(
                flags: ATEMProtocol.retransmitRequest,
                sessionID: sessionID,
                retransmitFromID: packetID
            )
        )
    }

    private func sendRaw(_ data: Data) {
        guard let networkConnection else {
            return
        }

        lastSentAt = clock.now
        if configuration.emitsPacketEvents {
            emit(.packet(.sent, data))
        }

        networkConnection.send(content: data, completion: .contentProcessed { [weak self] error in
            guard let self, let error else {
                return
            }
            self.queue.async {
                self.handleFailure(.networkUnavailable(error.localizedDescription))
            }
        })
    }

    private func acknowledgeOutboundPackets(through acknowledgementID: UInt16) {
        inFlightPackets.removeAll {
            isCoveredByAcknowledgement(
                acknowledgementID: acknowledgementID,
                packetID: $0.packetID
            )
        }
    }

    private func retransmit(from requestedID: UInt16) {
        let normalizedID = requestedID % ATEMProtocol.maximumPacketID
        guard let startIndex = inFlightPackets.firstIndex(
            where: { $0.packetID == normalizedID }
        ) else {
            emit(.diagnostic(
                "ATEM requested unavailable packet \(normalizedID); reconnecting."
            ))
            handleFailure(.packetRetriesExhausted(normalizedID))
            return
        }

        let now = clock.now
        for index in startIndex..<inFlightPackets.count {
            inFlightPackets[index].lastSentAt = now
            inFlightPackets[index].retryCount += 1
            sendRaw(inFlightPackets[index].data)
        }
    }

    private func startTimer() {
        timer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + .milliseconds(50), repeating: .milliseconds(50))
        timer.setEventHandler { [weak self] in
            self?.performMaintenance()
        }
        self.timer = timer
        timer.resume()
    }

    private func performMaintenance() {
        let now = clock.now

        if let lastReceivedAt,
           now - lastReceivedAt > .seconds(configuration.connectionTimeout) {
            handleFailure(.connectionTimedOut)
            return
        }

        if internalState == .established {
            if let lastSentAt,
               now - lastSentAt >= .seconds(configuration.keepaliveInterval),
               inFlightPackets.isEmpty {
                sendSequenced()
            }

            guard let oldest = inFlightPackets.first,
                  now - oldest.lastSentAt >= .seconds(configuration.retransmitTimeout)
            else {
                return
            }

            if oldest.retryCount >= configuration.maximumPacketRetries {
                handleFailure(.packetRetriesExhausted(oldest.packetID))
                return
            }

            retransmit(from: oldest.packetID)
        }
    }

    private func handleFailure(_ error: ATEMConnectionError) {
        guard internalState != .stopped else {
            return
        }

        emit(.diagnostic(error.localizedDescription))
        stopTransport()

        if !explicitlyDisconnected, configuration.automaticallyReconnects {
            setConnectionState(.reconnecting)
            let workItem = DispatchWorkItem { [weak self] in
                guard let self, !self.explicitlyDisconnected else {
                    return
                }
                self.beginConnection(isReconnect: true)
            }
            reconnectWorkItem = workItem
            queue.asyncAfter(
                deadline: .now() + configuration.reconnectDelay,
                execute: workItem
            )
        } else {
            setConnectionState(.failed(error))
        }
    }

    private func stopTransport() {
        internalState = .stopped
        networkConnection?.stateUpdateHandler = nil
        networkConnection?.cancel()
        networkConnection = nil
        timer?.cancel()
        timer = nil
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
        resetSession()
    }

    private func resetSession() {
        sessionID = 0
        nextSendPacketID = 1
        lastReceivedPacketID = 0
        lastReceivedAt = clock.now
        lastSentAt = nil
        inFlightPackets.removeAll(keepingCapacity: true)
        snapshotStorage = ATEMStateSnapshot()
    }

    private func setConnectionState(_ state: ATEMConnectionState) {
        guard connectionStateStorage != state else {
            return
        }
        connectionStateStorage = state
        emit(.connectionStateChanged(state))
    }

    private func emit(_ event: Event) {
        continuation.yield(event)
    }

    private func increment(_ packetID: UInt16) -> UInt16 {
        (packetID + 1) % ATEMProtocol.maximumPacketID
    }

    private func isCoveredByAcknowledgement(
        acknowledgementID: UInt16,
        packetID: UInt16
    ) -> Bool {
        let maximum = Int(ATEMProtocol.maximumPacketID)
        let tolerance = maximum / 2
        let acknowledgement = Int(acknowledgementID)
        let packet = Int(packetID)
        let forwardDistance = (acknowledgement - packet + maximum) % maximum
        return forwardDistance < tolerance
    }
}
