import Foundation
import Testing
@testable import Toma

@Suite struct CountdownTests {
    @Test func countsDownInOrderAndImmediateModeDoesNotTick() async throws {
        var ticks: [Int] = []
        try await Countdown.run(seconds: 3, interval: .milliseconds(1)) { ticks.append($0) }
        #expect(ticks == [3, 2, 1])
        ticks = []
        try await Countdown.run(seconds: 0, interval: .milliseconds(1)) { ticks.append($0) }
        #expect(ticks.isEmpty)
    }

    @Test func cancellationNeverReachesCapture() async throws {
        let entered = OneShot<Bool>()
        var captureStarted = false
        var ticks: [Int] = []
        let task = Task {
            try await Countdown.run(seconds: 3, interval: .seconds(10)) {
                ticks.append($0)
                entered.resolve(true)
            }
            captureStarted = true
        }
        _ = await entered.value
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(!captureStarted)
        #expect(ticks == [3])
    }
}
