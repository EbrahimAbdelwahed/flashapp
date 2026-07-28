import Testing
@testable import FlashUpData

@Suite("FlashUpData scaffold")
struct FlashUpDataScaffoldTests {
    @Test("Data layer links against the domain layer")
    func dataLayerLinksDomain() {
        #expect(FlashUpData.layerName == "FlashUpData")
        #expect(FlashUpData.domainLayerName == "FlashUpDomain")
    }
}
