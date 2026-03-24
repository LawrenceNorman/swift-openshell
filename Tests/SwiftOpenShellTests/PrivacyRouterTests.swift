import XCTest
@testable import SwiftOpenShell

final class PrivacyRouterTests: XCTestCase {

    func testHighSensitivityForcesLocal() {
        let router = PrivacyRouter()
        let decision = router.route(sensitivity: .confidential, complexity: .high)

        XCTAssertTrue(decision.isLocal)
        XCTAssertTrue(decision.reason.contains("sensitivity"))
    }

    func testRestrictedForcesLocal() {
        let router = PrivacyRouter()
        let decision = router.route(sensitivity: .restricted)

        XCTAssertTrue(decision.isLocal)
    }

    func testPublicAllowsCloud() {
        let router = PrivacyRouter()
        let decision = router.route(sensitivity: .public, complexity: .high)

        XCTAssertFalse(decision.isLocal)
    }

    func testPreferredProvider() {
        let router = PrivacyRouter()
        let decision = router.route(sensitivity: .public, preferredProvider: "openai")

        XCTAssertEqual(decision.provider, "openai")
        XCTAssertFalse(decision.isLocal)
    }

    func testCostOptimizedLocalForLowComplexity() {
        let config = PrivacyRouter.Config(
            localProviders: [PrivacyRouter.LocalProvider(name: "ollama", model: "llama3.2")],
            preferLocalForCost: true
        )
        let router = PrivacyRouter(config: config)
        let decision = router.route(sensitivity: .public, complexity: .low)

        XCTAssertTrue(decision.isLocal)
        XCTAssertTrue(decision.reason.contains("cost"))
    }

    func testRoutingMatrixCoversAllCombinations() {
        let router = PrivacyRouter()
        let matrix = router.routingMatrix()

        XCTAssertEqual(matrix.count, SensitivityLevel.allCases.count * ComplexityLevel.allCases.count)
    }

    func testGPUProviderForHighComplexitySensitive() {
        let config = PrivacyRouter.Config(
            localProviders: [
                PrivacyRouter.LocalProvider(name: "ollama", model: "llama3.2"),
                PrivacyRouter.LocalProvider(name: "nemotron", model: "nemotron-120b", isGPUAccelerated: true),
            ]
        )
        let router = PrivacyRouter(config: config)
        let decision = router.route(sensitivity: .restricted, complexity: .high)

        XCTAssertTrue(decision.isLocal)
        XCTAssertEqual(decision.provider, "nemotron")
    }
}
