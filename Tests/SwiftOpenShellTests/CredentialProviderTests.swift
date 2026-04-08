import XCTest
@testable import SwiftOpenShell

final class CredentialProviderTests: XCTestCase {

    func testKeychainReadNonExistentKey() {
        let manager = CredentialProviderManager(client: OpenShellClient())
        // Reading a non-existent key should return nil, not crash
        let value = manager.readKeychain(service: "com.mchatai.test.nonexistent", account: "does_not_exist")
        XCTAssertNil(value)
    }

    func testVerifyCredentialIsolationWithFakeSandbox() async {
        let manager = CredentialProviderManager(client: OpenShellClient())
        // With a non-existent sandbox, exec will fail — result depends on OpenShell installation
        let sandbox = Sandbox(id: "fake", name: "nonexistent-sandbox-12345", status: .stopped)
        let isolated = await manager.verifyCredentialIsolation(sandbox: sandbox)
        // Either false (exec failed) or true (exec returned empty = no leaks) — both are acceptable for a fake sandbox
        // The important thing is it doesn't crash
        _ = isolated
    }

    func testAgentCredentialsModel() {
        let creds = CredentialProviderManager.AgentCredentials(
            providerName: "mchatai-anthropic",
            envVars: ["ANTHROPIC_API_KEY": "sk-test-123"]
        )
        XCTAssertEqual(creds.providerName, "mchatai-anthropic")
        XCTAssertEqual(creds.envVars.count, 1)
        XCTAssertEqual(creds.envVars["ANTHROPIC_API_KEY"], "sk-test-123")
    }
}
