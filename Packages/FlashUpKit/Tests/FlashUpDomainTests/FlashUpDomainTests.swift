import Testing
@testable import FlashUpDomain

@Suite("FlashUpDomain scaffold")
struct FlashUpDomainScaffoldTests {
    @Test("Domain layer is reachable from a simulator-free test run")
    func domainLayerIsReachable() {
        #expect(FlashUpDomain.layerName == "FlashUpDomain")
    }
}
