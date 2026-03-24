import XCTest
@testable import SwiftOpenShell

final class PolicyManagerTests: XCTestCase {
    var manager: PolicyManager!

    override func setUp() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("SwiftOpenShellTests-\(UUID().uuidString)")
        manager = PolicyManager(policyDirectory: dir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: manager.policyDirectory)
    }

    func testGenerateYAML() {
        let policy = manager.template(.developer, workspaceRoot: "/Users/dev/project")
        let yaml = manager.generateYAML(from: policy)

        XCTAssertTrue(yaml.contains("version: 1"))
        XCTAssertTrue(yaml.contains("filesystem_policy:"))
        XCTAssertTrue(yaml.contains("include_workdir: true"))
        XCTAssertTrue(yaml.contains("/Users/dev/project"))
        XCTAssertTrue(yaml.contains("api.anthropic.com"))
        XCTAssertTrue(yaml.contains("*.github.com"))
    }

    func testSaveAndList() throws {
        let policy = manager.template(.developer)
        let url = try manager.save(policy: policy)

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(url.lastPathComponent.hasSuffix(".yaml"))

        let saved = manager.listSavedPolicies()
        XCTAssertTrue(saved.contains(where: { $0.lastPathComponent == url.lastPathComponent }))
    }

    func testAllTemplates() {
        for template in PolicyManager.Template.allCases {
            let policy = manager.template(template, workspaceRoot: "/tmp/test")
            let yaml = manager.generateYAML(from: policy)

            XCTAssertTrue(yaml.contains("version: 1"), "Template \(template.rawValue) missing version")
            XCTAssertTrue(yaml.contains("filesystem_policy:"), "Template \(template.rawValue) missing filesystem_policy")
            XCTAssertTrue(yaml.contains("process:"), "Template \(template.rawValue) missing process")
        }
    }

    func testPrivateTemplateHasNoNetwork() {
        let policy = manager.template(.privateAirGapped)
        XCTAssertTrue(policy.networkPolicies.isEmpty, "Private agent should have no network policies")

        let yaml = manager.generateYAML(from: policy)
        XCTAssertFalse(yaml.contains("network_policies:"))
    }

    func testMigrateFromCommandPolicy() {
        let policy = manager.migrateFromCommandPolicy(
            workspaceRoot: "/Users/dev/project",
            readOnlyMode: true,
            blockedCommands: ["rm -rf /", "sudo"],
            allowedDomains: ["api.anthropic.com", "api.openai.com"]
        )

        XCTAssertTrue(policy.filesystemPolicy.readOnly.contains("/Users/dev/project"))
        XCTAssertFalse(policy.filesystemPolicy.readWrite.contains("/Users/dev/project"))
        XCTAssertEqual(policy.process.denySpawn, ["rm -rf /", "sudo"])
        XCTAssertEqual(policy.networkPolicies.first?.endpoints.count, 2)
    }
}
