import Foundation

enum ATEMProtocol {
    static let port: UInt16 = 9910
    static let headerLength = 12
    static let maximumPacketID: UInt16 = 1 << 15

    // Packet flags occupy the upper five bits of the first UInt16.
    static let ackRequest: UInt8 = 0x01
    static let newSessionID: UInt8 = 0x02
    static let isRetransmit: UInt8 = 0x04
    static let retransmitRequest: UInt8 = 0x08
    static let ackReply: UInt8 = 0x10

    // The maintained Sofie handshake. Bytes 2–3 are replaced with a fresh
    // initiation ID for every connection; the ATEM returns its assigned
    // session ID in the new-session response.
    static let connectHelloTemplate = Data([
        0x10, 0x14, 0x53, 0xab, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x3a, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00,
    ])

    enum CommandName {
        // State messages sent by the switcher.
        static let programInput = "PrgI"
        static let previewInput = "PrvI"
        static let transitionPosition = "TrPs"
        static let fadeToBlackState = "FtbS"
        static let initialSyncComplete = "InCm"

        // Control messages sent by a controller.
        static let setProgramInput = "CPgI"
        static let setPreviewInput = "CPvI"
        static let cut = "DCut"
        static let autoTransition = "DAut"
        static let fadeToBlack = "FtbA"
    }

    static func freshInitiationID() -> UInt16 {
        UInt16.random(in: 1...0x7fff)
    }

    static func connectHello(initiationID: UInt16) -> Data {
        var packet = connectHelloTemplate
        packet.setUInt16BE(initiationID & 0x7fff, at: 2)
        return packet
    }

    static func packet(
        flags: UInt8,
        sessionID: UInt16,
        acknowledgementID: UInt16 = 0,
        retransmitFromID: UInt16 = 0,
        packetID: UInt16 = 0,
        payload: Data = Data()
    ) -> Data {
        let length = headerLength + payload.count
        precondition(length <= 0x07ff, "ATEM packet exceeds 11-bit length field")

        var result = Data(repeating: 0, count: headerLength)
        result.setUInt16BE((UInt16(flags) << 11) | UInt16(length), at: 0)
        result.setUInt16BE(sessionID, at: 2)
        result.setUInt16BE(acknowledgementID, at: 4)
        result.setUInt16BE(retransmitFromID, at: 6)
        result.setUInt16BE(packetID, at: 10)
        result.append(payload)
        return result
    }

    static func command(name: String, body: Data) -> Data {
        precondition(name.utf8.count == 4, "ATEM command names are four ASCII bytes")

        var result = Data()
        result.appendUInt16BE(UInt16(8 + body.count))
        result.append(contentsOf: [0, 0])
        result.append(contentsOf: name.utf8)
        result.append(body)
        return result
    }

    static func busCommand(name: String, source: UInt16) -> Data {
        var body = Data([0, 0]) // Mix Effect 0, reserved.
        body.appendUInt16BE(source)
        return command(name: name, body: body)
    }

    static func transitionCommand(name: String) -> Data {
        command(name: name, body: Data(repeating: 0, count: 4))
    }

    static func transitionState(from body: Data) -> ATEMTransitionState? {
        guard body.count >= 6,
              body[0] == 0,
              let handlePosition = body.uint16BE(at: 4)
        else {
            return nil
        }

        return ATEMTransitionState(
            isInTransition: body[1] == 1,
            remainingFrames: body[2],
            handlePosition: handlePosition
        )
    }

    static func fadeToBlackState(from body: Data) -> ATEMFadeToBlackState? {
        guard body.count >= 4, body[0] == 0 else {
            return nil
        }

        return ATEMFadeToBlackState(
            isFullyBlack: body[1] == 1,
            isInTransition: body[2] == 1,
            remainingFrames: body[3]
        )
    }
}

struct ATEMPacketHeader: Equatable {
    let length: Int
    let flags: UInt8
    let sessionID: UInt16
    let acknowledgementID: UInt16
    let retransmitFromID: UInt16
    let packetID: UInt16

    static func parse(_ data: Data) throws -> ATEMPacketHeader {
        guard data.count >= ATEMProtocol.headerLength,
              let opcodeAndLength = data.uint16BE(at: 0),
              let sessionID = data.uint16BE(at: 2),
              let acknowledgementID = data.uint16BE(at: 4),
              let retransmitFromID = data.uint16BE(at: 6),
              let packetID = data.uint16BE(at: 10)
        else {
            throw ATEMConnectionError.malformedPacket("fewer than 12 header bytes")
        }

        let length = Int(opcodeAndLength & 0x07ff)
        guard length == data.count else {
            throw ATEMConnectionError.malformedPacket(
                "declared length \(length) does not match datagram length \(data.count)"
            )
        }

        return ATEMPacketHeader(
            length: length,
            flags: UInt8(opcodeAndLength >> 11),
            sessionID: sessionID,
            acknowledgementID: acknowledgementID,
            retransmitFromID: retransmitFromID,
            packetID: packetID
        )
    }

    func contains(_ flag: UInt8) -> Bool {
        flags & flag != 0
    }
}

enum ATEMCommandParser {
    static func parse(_ payload: Data) throws -> [ATEMRawCommand] {
        var commands: [ATEMRawCommand] = []
        var offset = 0

        while offset < payload.count {
            guard payload.count - offset >= 8,
                  let declaredLength = payload.uint16BE(at: offset)
            else {
                throw ATEMConnectionError.malformedPacket(
                    "trailing command data is shorter than its 8-byte header"
                )
            }

            let length = Int(declaredLength)
            guard length >= 8 else {
                throw ATEMConnectionError.malformedPacket(
                    "command at offset \(offset) declares invalid length \(length)"
                )
            }
            guard offset + length <= payload.count else {
                throw ATEMConnectionError.malformedPacket(
                    "command at offset \(offset) extends past the datagram"
                )
            }

            let nameRange = (offset + 4)..<(offset + 8)
            guard let name = String(
                data: payload.subdata(in: nameRange),
                encoding: .ascii
            ) else {
                throw ATEMConnectionError.malformedPacket(
                    "command at offset \(offset) has a non-ASCII identifier"
                )
            }

            commands.append(
                ATEMRawCommand(
                    name: name,
                    body: payload.subdata(in: (offset + 8)..<(offset + length))
                )
            )
            offset += length
        }

        return commands
    }
}
