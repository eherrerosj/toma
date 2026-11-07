import Testing
@testable import Toma

@Suite struct ResourceBudgetTests {
    @Test func captureStopsBeforeDiskExhaustionOrAnUnboundedRecording() {
        #expect(ResourceBudget.stopReason(elapsed: 1, bytes: 1, available: 1) != nil)
        #expect(ResourceBudget.stopReason(elapsed: 3_601, bytes: 1, available: 1_000_000_000) != nil)
        #expect(ResourceBudget.stopReason(elapsed: 1, bytes: 5_000_000_000, available: 1_000_000_000) != nil)
        #expect(ResourceBudget.stopReason(elapsed: 1, bytes: 1, available: 1_000_000_000) == nil)
    }

    @Test func gifConcurrencyFitsItsWorkingSetBudget() {
        #expect(ResourceBudget.gifBatchSize(width: 1920, height: 1080, processors: 64) == 1)
        #expect(ResourceBudget.gifBatchSize(width: 640, height: 360, processors: 64) <= 4)
        #expect(ResourceBudget.gifBatchSize(width: 640, height: 360, processors: 1) == 1)
    }
}
