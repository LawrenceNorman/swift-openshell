import XCTest
@testable import SwiftOpenShell

final class AuditLogParserTests: XCTestCase {
    let parser = AuditLogParser()

    func testParseNetworkEvent() {
        let json = """
        {"class_uid": 4001, "time": 1711234567.0, "activity_name": "Connect", "status_id": 1, "dst_endpoint": {"hostname": "api.anthropic.com", "port": 443}, "process": {"name": "claude"}, "sandbox_name": "test-sandbox"}
        """
        let event = parser.parse(line: json)

        XCTAssertNotNil(event)
        XCTAssertEqual(event?.category, .network)
        XCTAssertEqual(event?.action, "Connect")
        XCTAssertEqual(event?.outcome, .allowed)
        XCTAssertEqual(event?.sandboxName, "test-sandbox")
        XCTAssertEqual(event?.details["host"], "api.anthropic.com")
    }

    func testParseDeniedEvent() {
        let json = """
        {"class_uid": 4001, "time": 1711234567.0, "activity_name": "Connect", "status_id": 2, "dst_endpoint": {"hostname": "evil.com", "port": 443}, "sandbox_name": "test"}
        """
        let event = parser.parse(line: json)

        XCTAssertEqual(event?.outcome, .denied)
        XCTAssertEqual(event?.details["host"], "evil.com")
    }

    func testParseFilesystemEvent() {
        let json = """
        {"class_uid": 1001, "time": 1711234567.0, "activity_name": "Read", "status_id": 1, "file": {"path": "/etc/passwd"}, "sandbox_name": "test"}
        """
        let event = parser.parse(line: json)

        XCTAssertEqual(event?.category, .filesystem)
        XCTAssertEqual(event?.details["path"], "/etc/passwd")
    }

    func testParseInvalidLine() {
        let event = parser.parse(line: "this is not json")
        XCTAssertNil(event)
    }

    func testSummary() {
        let events = [
            AuditEvent(timestamp: Date(), sandboxName: "test", category: .network, action: "Connect", outcome: .allowed, details: ["host": "api.anthropic.com"]),
            AuditEvent(timestamp: Date(), sandboxName: "test", category: .network, action: "Connect", outcome: .denied, details: ["host": "evil.com"]),
            AuditEvent(timestamp: Date(), sandboxName: "test", category: .filesystem, action: "Read", outcome: .allowed, details: ["path": "/etc/hosts"]),
        ]

        let summary = parser.summary(events: events)

        XCTAssertEqual(summary.totalEvents, 3)
        XCTAssertEqual(summary.allowed, 2)
        XCTAssertEqual(summary.denied, 1)
        XCTAssertEqual(summary.uniqueHostsAccessed.count, 2)
        XCTAssertEqual(summary.uniqueFilesAccessed.count, 1)
    }
}
