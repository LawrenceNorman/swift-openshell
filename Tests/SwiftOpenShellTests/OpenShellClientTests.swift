import XCTest
@testable import SwiftOpenShell

final class OpenShellClientTests: XCTestCase {
    let client = OpenShellClient()

    func testDetectReturnsValidInfo() async {
        let info = await client.detect()
        // On CI or dev machines without OpenShell, isInstalled will be false — that's OK
        XCTAssertNotNil(info)
        if info.isInstalled {
            XCTAssertNotNil(info.version)
            XCTAssertTrue(info.gatewayStatus != .notInstalled)
        } else {
            XCTAssertEqual(info.gatewayStatus, .notInstalled)
        }
    }

    func testSandboxConfigDefaults() {
        let config = SandboxConfig(agent: "claude")
        XCTAssertEqual(config.agent, "claude")
        XCTAssertNil(config.name)
        XCTAssertNil(config.policyPath)
        XCTAssertNil(config.workdir)
        XCTAssertTrue(config.providers.isEmpty)
        XCTAssertFalse(config.gpu)
        XCTAssertTrue(config.extraArgs.isEmpty)
    }

    func testSandboxConfigWithAllOptions() {
        let config = SandboxConfig(
            name: "test-sandbox",
            agent: "codex",
            policyPath: "/tmp/policy.yaml",
            workdir: "/Users/dev/project",
            providers: ["mchatai-openai"],
            gpu: true,
            extraArgs: ["--verbose"]
        )
        XCTAssertEqual(config.name, "test-sandbox")
        XCTAssertEqual(config.agent, "codex")
        XCTAssertEqual(config.policyPath, "/tmp/policy.yaml")
        XCTAssertEqual(config.workdir, "/Users/dev/project")
        XCTAssertEqual(config.providers, ["mchatai-openai"])
        XCTAssertTrue(config.gpu)
        XCTAssertEqual(config.extraArgs, ["--verbose"])
    }

    func testExecResultSucceeded() {
        let success = ExecResult(exitCode: 0, stdout: "hello", stderr: "", duration: 0.5)
        XCTAssertTrue(success.succeeded)
        XCTAssertEqual(success.exitCode, 0)

        let failure = ExecResult(exitCode: 1, stdout: "", stderr: "error", duration: 0.1)
        XCTAssertFalse(failure.succeeded)
    }

    func testSandboxModelProperties() {
        let sandbox = Sandbox(
            id: "test-1",
            name: "mchatai-claude-abc12345",
            status: .running,
            createdAt: Date(),
            agent: "claude",
            policyName: "developer-agent.yaml",
            gpuEnabled: false
        )
        XCTAssertEqual(sandbox.id, "test-1")
        XCTAssertEqual(sandbox.name, "mchatai-claude-abc12345")
        XCTAssertEqual(sandbox.status, .running)
        XCTAssertEqual(sandbox.agent, "claude")
        XCTAssertFalse(sandbox.gpuEnabled)
    }

    func testCredentialProviderModel() {
        let provider = CredentialProvider(
            name: "mchatai-anthropic",
            type: .env,
            envKeys: ["ANTHROPIC_API_KEY"]
        )
        XCTAssertEqual(provider.name, "mchatai-anthropic")
        XCTAssertEqual(provider.type, .env)
        XCTAssertEqual(provider.envKeys, ["ANTHROPIC_API_KEY"])
    }

    func testOpenShellErrorDescriptions() {
        let errors: [OpenShellError] = [
            .notInstalled,
            .dockerNotAvailable,
            .gatewayNotRunning,
            .sandboxCreateFailed("test"),
            .sandboxNotFound("test"),
            .execFailed("test"),
            .policyInvalid("test"),
            .providerFailed("test"),
            .timeout,
            .commandFailed(exitCode: 1, stderr: "error")
        ]
        for error in errors {
            XCTAssertNotNil(error.errorDescription)
            XCTAssertFalse(error.errorDescription!.isEmpty)
        }
    }

    func testSensitivityLevelComparison() {
        XCTAssertTrue(SensitivityLevel.public < SensitivityLevel.internal)
        XCTAssertTrue(SensitivityLevel.internal < SensitivityLevel.confidential)
        XCTAssertTrue(SensitivityLevel.confidential < SensitivityLevel.restricted)
    }

    func testSensitivityLevelLabels() {
        for level in SensitivityLevel.allCases {
            XCTAssertFalse(level.label.isEmpty)
        }
    }

    func testGatewayStatusValues() {
        let statuses: [GatewayStatus] = [.running, .stopped, .notInstalled, .dockerNotRunning, .unknown]
        XCTAssertEqual(statuses.count, 5)
    }

    func testSandboxStatusValues() {
        let statuses: [SandboxStatus] = [.creating, .running, .stopped, .failed, .destroying, .unknown]
        XCTAssertEqual(statuses.count, 6)
    }
}
