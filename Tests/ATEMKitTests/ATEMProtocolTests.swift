import XCTest
@testable import ATEMKit

final class ATEMProtocolTests: XCTestCase {
    func testConnectHelloUsesFreshInitiationID() {
        let packet = ATEMProtocol.connectHello(initiationID: 0x1234)

        XCTAssertEqual(packet.count, 20)
        XCTAssertEqual(packet.uint16BE(at: 0), 0x1014)
        XCTAssertEqual(packet.uint16BE(at: 2), 0x1234)
        XCTAssertEqual(packet[9], 0x3a)
        XCTAssertEqual(packet[12], 0x01)
    }

    func testPhysicalATEMHandshakeUsesDifferentAssignedSession() throws {
        let handshakeResponse = Data([
            0x10, 0x14, 0x4b, 0xe8, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x10,
            0x00, 0x00, 0x00, 0x00,
        ])
        let firstStatePacketHeader = Data([
            0x08, 0x0c, 0x80, 0x10, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x01,
        ])

        let handshake = try ATEMPacketHeader.parse(handshakeResponse)
        let firstState = try ATEMPacketHeader.parse(firstStatePacketHeader)

        XCTAssertTrue(handshake.contains(ATEMProtocol.newSessionID))
        XCTAssertEqual(handshake.sessionID, 0x4be8)
        XCTAssertTrue(firstState.contains(ATEMProtocol.ackRequest))
        XCTAssertEqual(firstState.sessionID, 0x8010)
        XCTAssertNotEqual(handshake.sessionID, firstState.sessionID)
    }

    func testAcknowledgementPacketEncoding() throws {
        let packet = ATEMProtocol.packet(
            flags: ATEMProtocol.ackReply,
            sessionID: 0x5360,
            acknowledgementID: 0x0041
        )

        XCTAssertEqual(packet.hexString(), "800c53600041000000000000")
        let header = try ATEMPacketHeader.parse(packet)
        XCTAssertTrue(header.contains(ATEMProtocol.ackReply))
        XCTAssertEqual(header.sessionID, 0x5360)
        XCTAssertEqual(header.acknowledgementID, 0x0041)
    }

    func testProgramCommandMatchesReferenceLayout() {
        let command = ATEMProtocol.busCommand(
            name: ATEMProtocol.CommandName.setProgramInput,
            source: 4
        )

        XCTAssertEqual(command.hexString(), "000c00004350674900000004")
    }

    func testPreviewCommandMatchesReferenceLayout() {
        let command = ATEMProtocol.busCommand(
            name: ATEMProtocol.CommandName.setPreviewInput,
            source: 2
        )

        XCTAssertEqual(command.hexString(), "000c00004350764900000002")
    }

    func testTransitionCommandsMatchReferenceLayout() {
        XCTAssertEqual(
            ATEMProtocol.transitionCommand(name: ATEMProtocol.CommandName.cut)
                .hexString(),
            "000c00004443757400000000"
        )
        XCTAssertEqual(
            ATEMProtocol.transitionCommand(
                name: ATEMProtocol.CommandName.autoTransition
            ).hexString(),
            "000c00004441757400000000"
        )
    }

    func testParsesMultipleCommands() throws {
        var payload = Data()
        payload.append(
            ATEMProtocol.command(
                name: ATEMProtocol.CommandName.programInput,
                body: Data([0, 0, 0, 3])
            )
        )
        payload.append(
            ATEMProtocol.command(
                name: ATEMProtocol.CommandName.initialSyncComplete,
                body: Data()
            )
        )

        let commands = try ATEMCommandParser.parse(payload)

        XCTAssertEqual(commands.count, 2)
        XCTAssertEqual(commands[0].name, "PrgI")
        XCTAssertEqual(commands[0].body, Data([0, 0, 0, 3]))
        XCTAssertEqual(commands[1].name, "InCm")
        XCTAssertTrue(commands[1].body.isEmpty)
    }

    func testRejectsDatagramWithMismatchedLength() {
        var packet = ATEMProtocol.packet(
            flags: ATEMProtocol.ackRequest,
            sessionID: 1,
            packetID: 1
        )
        packet.append(0)

        XCTAssertThrowsError(try ATEMPacketHeader.parse(packet))
    }

    func testRejectsCommandThatExtendsPastPayload() {
        let payload = Data([0, 12, 0, 0, 0x50, 0x72, 0x67, 0x49])

        XCTAssertThrowsError(try ATEMCommandParser.parse(payload))
    }
}
