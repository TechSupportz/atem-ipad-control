import Foundation

public struct ATEMStateSnapshot: Equatable, Sendable {
    public internal(set) var programInput: UInt16?
    public internal(set) var previewInput: UInt16?
    public internal(set) var isInitialSyncComplete: Bool

    public init(
        programInput: UInt16? = nil,
        previewInput: UInt16? = nil,
        isInitialSyncComplete: Bool = false
    ) {
        self.programInput = programInput
        self.previewInput = previewInput
        self.isInitialSyncComplete = isInitialSyncComplete
    }
}

public enum ATEMConnectionState: Equatable, Sendable {
    case disconnected
    case connecting
    case synchronizing
    case connected
    case reconnecting
    case failed(ATEMConnectionError)
}

public enum ATEMConnectionError: Error, Equatable, Sendable {
    case invalidHost(String)
    case connectionTimedOut
    case networkUnavailable(String)
    case malformedPacket(String)
    case packetRetriesExhausted(UInt16)
    case disconnected
}

extension ATEMConnectionError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .invalidHost(host):
            return "The ATEM host “\(host)” is not a valid IPv4 address."
        case .connectionTimedOut:
            return "No ATEM packets were received before the connection timed out."
        case let .networkUnavailable(message):
            return "The local network is unavailable: \(message)"
        case let .malformedPacket(message):
            return "The ATEM sent a malformed packet: \(message)"
        case let .packetRetriesExhausted(packetID):
            return "ATEM packet \(packetID) was not acknowledged after all retries."
        case .disconnected:
            return "The ATEM connection was closed."
        }
    }
}

public struct ATEMRawCommand: Equatable, Sendable {
    public let name: String
    public let body: Data

    public init(name: String, body: Data) {
        self.name = name
        self.body = body
    }
}

public enum ATEMPacketDirection: String, Sendable {
    case sent = "SEND"
    case received = "RECV"
}
