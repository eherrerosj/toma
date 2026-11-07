import Foundation
import Testing
@testable import Toma

@Suite struct DeadlineTests {
    @Test func missingDelegateCallbackTimesOutAndCanResolveLater() async throws {
        let signal = OneShot<Bool>()
        await #expect(throws: (any Error).self) { try await signal.wait(timeout: .milliseconds(20)) }
        signal.resolve(true)
        #expect(try await signal.wait(timeout: .seconds(1)))
    }

    @Test func cancellationRemovesWaiterWithoutWaitingForADelegate() async {
        let signal = OneShot<Bool>()
        let task = Task { try await signal.wait(timeout: .seconds(60)) }
        task.cancel()
        await #expect(throws: (any Error).self) { try await task.value }
    }

    @Test func hungToolIsTerminatedAtItsDeadline() async {
        let start = ContinuousClock.now
        await #expect(throws: (any Error).self) {
            try await ToolRunner.run("/bin/sleep", ["20"], timeout: .milliseconds(50))
        }
        #expect(ContinuousClock.now - start < .seconds(2))
    }

    @Test func toolOutputIsDrainedAndExitFailureIsReported() async throws {
        #expect(try await ToolRunner.run("/usr/bin/printf", ["hello"]) == "hello")
        await #expect(throws: (any Error).self) { try await ToolRunner.run("/usr/bin/false", []) }
    }
}
