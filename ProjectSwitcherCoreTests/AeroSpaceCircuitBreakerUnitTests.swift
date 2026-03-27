import XCTest
@testable import ProjectSwitcherCore

// MARK: - Circuit Breaker Unit Tests

final class AeroSpaceCircuitBreakerTests: XCTestCase {

    func testInitialStateIsClosed() {
        let breaker = AeroSpaceCircuitBreaker(cooldownSeconds: 10)
        XCTAssertEqual(breaker.currentState, .closed)
        XCTAssertTrue(breaker.shouldAllow())
    }

    func testRecordTimeoutTripsBreaker() {
        let breaker = AeroSpaceCircuitBreaker(cooldownSeconds: 10)

        breaker.recordTimeout()

        XCTAssertFalse(breaker.shouldAllow())
        if case .open = breaker.currentState {} else {
            XCTFail("Expected open state after timeout")
        }
    }

    func testBreakerFailsFastWhenOpen() {
        let breaker = AeroSpaceCircuitBreaker(cooldownSeconds: 60)

        breaker.recordTimeout()

        // Multiple calls should all be rejected
        XCTAssertFalse(breaker.shouldAllow())
        XCTAssertFalse(breaker.shouldAllow())
        XCTAssertFalse(breaker.shouldAllow())
    }

    func testBreakerRecoverAfterCooldown() {
        // Use a tiny cooldown so the test doesn't sleep long
        let breaker = AeroSpaceCircuitBreaker(cooldownSeconds: 0.05)

        breaker.recordTimeout()
        XCTAssertFalse(breaker.shouldAllow())

        // Wait for cooldown to expire
        Thread.sleep(forTimeInterval: 0.1)

        XCTAssertTrue(breaker.shouldAllow())
        XCTAssertEqual(breaker.currentState, .closed)
    }

    func testRecordSuccessClosesBreaker() {
        let breaker = AeroSpaceCircuitBreaker(cooldownSeconds: 60)

        breaker.recordTimeout()
        XCTAssertFalse(breaker.shouldAllow())

        breaker.recordSuccess()
        XCTAssertTrue(breaker.shouldAllow())
        XCTAssertEqual(breaker.currentState, .closed)
    }

    func testResetClosesBreaker() {
        let breaker = AeroSpaceCircuitBreaker(cooldownSeconds: 60)

        breaker.recordTimeout()
        XCTAssertFalse(breaker.shouldAllow())

        breaker.reset()
        XCTAssertTrue(breaker.shouldAllow())
        XCTAssertEqual(breaker.currentState, .closed)
    }

    // MARK: - Recovery Tracking

    func testShouldAttemptRecoveryWhenOpenAndUnderLimit() {
        let breaker = AeroSpaceCircuitBreaker(cooldownSeconds: 60)
        breaker.recordTimeout()
        XCTAssertTrue(breaker.shouldAttemptRecovery())
    }

    func testShouldNotAttemptRecoveryWhenClosed() {
        let breaker = AeroSpaceCircuitBreaker(cooldownSeconds: 60)
        XCTAssertFalse(breaker.shouldAttemptRecovery())
    }

    func testShouldNotAttemptRecoveryAfterCooldownExpired() {
        let breaker = AeroSpaceCircuitBreaker(cooldownSeconds: 0.01)
        breaker.recordTimeout()
        Thread.sleep(forTimeInterval: 0.05)
        XCTAssertFalse(breaker.shouldAttemptRecovery())
    }

    func testBeginRecoveryReturnsTrueFirstTime() {
        let breaker = AeroSpaceCircuitBreaker(cooldownSeconds: 60)
        breaker.recordTimeout()
        XCTAssertTrue(breaker.beginRecovery())
        XCTAssertTrue(breaker.isRecoveryInProgress)
    }

    func testBeginRecoveryReturnsFalseWhenAlreadyInProgress() {
        let breaker = AeroSpaceCircuitBreaker(cooldownSeconds: 60)
        breaker.recordTimeout()
        XCTAssertTrue(breaker.beginRecovery())
        XCTAssertFalse(breaker.beginRecovery(), "Second concurrent recovery should be rejected")
    }

    func testBeginRecoveryReturnsFalseWhenClosed() {
        let breaker = AeroSpaceCircuitBreaker(cooldownSeconds: 60)
        XCTAssertFalse(breaker.beginRecovery())
    }

    func testEndRecoverySuccessResetsBreaker() {
        let breaker = AeroSpaceCircuitBreaker(cooldownSeconds: 60)
        breaker.recordTimeout()
        _ = breaker.beginRecovery()
        breaker.endRecovery(success: true)

        XCTAssertFalse(breaker.isRecoveryInProgress)
        XCTAssertEqual(breaker.currentState, .closed)
        XCTAssertTrue(breaker.shouldAllow())
    }

    func testEndRecoveryFailureIncrementsCount() {
        let breaker = AeroSpaceCircuitBreaker(cooldownSeconds: 60)
        breaker.recordTimeout()
        _ = breaker.beginRecovery()
        breaker.endRecovery(success: false)

        XCTAssertFalse(breaker.isRecoveryInProgress)
        // Should still allow one more attempt
        XCTAssertTrue(breaker.shouldAttemptRecovery())
    }

    func testEndRecoveryFailureReopensBreaker() {
        // When recovery fails (e.g., start() launched AeroSpace but readiness
        // timed out), start() may have reset the breaker to closed. endRecovery
        // must re-open it so subsequent calls continue to fail fast.
        let breaker = AeroSpaceCircuitBreaker(cooldownSeconds: 60)
        breaker.recordTimeout()
        _ = breaker.beginRecovery()

        // Simulate what start() does: reset breaker to closed mid-recovery
        breaker.reset()

        breaker.endRecovery(success: false)

        // Breaker must be open (not closed) to maintain fail-fast
        if case .open = breaker.currentState {} else {
            XCTFail("Expected breaker to be re-opened after failed recovery, got \(breaker.currentState)")
        }
        XCTAssertFalse(breaker.shouldAllow(), "Should fail fast after failed recovery")
    }

    func testMaxRecoveryAttemptsExhausted() {
        let breaker = AeroSpaceCircuitBreaker(cooldownSeconds: 60)

        // Exhaust all recovery attempts
        for _ in 0..<AeroSpaceCircuitBreaker.maxRecoveryAttempts {
            breaker.recordTimeout()
            XCTAssertTrue(breaker.beginRecovery())
            breaker.endRecovery(success: false)
        }

        // Should no longer attempt recovery
        XCTAssertFalse(breaker.shouldAttemptRecovery())
        XCTAssertFalse(breaker.beginRecovery())
    }

    func testRecordSuccessClearsRecoveryCount() {
        let breaker = AeroSpaceCircuitBreaker(cooldownSeconds: 60)

        // One failed recovery
        breaker.recordTimeout()
        _ = breaker.beginRecovery()
        breaker.endRecovery(success: false)

        // A normal success resets everything
        breaker.recordSuccess()

        // Trip again — recovery should be available from zero
        breaker.recordTimeout()
        XCTAssertTrue(breaker.shouldAttemptRecovery())
    }

    func testResetClearsRecoveryState() {
        let breaker = AeroSpaceCircuitBreaker(cooldownSeconds: 60)
        breaker.recordTimeout()
        _ = breaker.beginRecovery()

        breaker.reset()

        XCTAssertFalse(breaker.isRecoveryInProgress)
        XCTAssertEqual(breaker.currentState, .closed)
    }

    func testNewTripAfterCooldownResetsRecoveryBudget() {
        let breaker = AeroSpaceCircuitBreaker(cooldownSeconds: 0.01)

        // Exhaust recovery attempts on first trip
        breaker.recordTimeout()
        for _ in 0..<AeroSpaceCircuitBreaker.maxRecoveryAttempts {
            _ = breaker.beginRecovery()
            breaker.endRecovery(success: false)
        }
        XCTAssertFalse(breaker.shouldAttemptRecovery(), "Should be exhausted")

        // Wait for cooldown → breaker transitions back to closed
        Thread.sleep(forTimeInterval: 0.05)
        XCTAssertTrue(breaker.shouldAllow())

        // New trip should reset recovery budget
        breaker.recordTimeout()
        XCTAssertTrue(breaker.shouldAttemptRecovery(), "New trip should have fresh recovery budget")
    }

    func testRetripWhileOpenDoesNotResetRecoveryBudget() {
        let breaker = AeroSpaceCircuitBreaker(cooldownSeconds: 60)

        // First trip, exhaust one attempt
        breaker.recordTimeout()
        _ = breaker.beginRecovery()
        breaker.endRecovery(success: false)

        // Re-trip while still open (extends cooldown but same outage)
        breaker.recordTimeout()

        // Should still have only 1 attempt remaining, not reset to 2
        _ = breaker.beginRecovery()
        breaker.endRecovery(success: false)
        XCTAssertFalse(breaker.shouldAttemptRecovery(), "Re-trip while open should not reset budget")
    }

    func testMultipleTimeoutsExtendCooldown() {
        // Verify that a second recordTimeout() pushes the expiry forward,
        // proving cooldown is reset (not accumulated or ignored).
        // Uses state inspection instead of Thread.sleep to avoid CI flakiness.
        let breaker = AeroSpaceCircuitBreaker(cooldownSeconds: 10)

        breaker.recordTimeout()
        guard case .open(let firstExpiry) = breaker.currentState else {
            return XCTFail("Expected open state after first timeout")
        }

        // Small delay so Date() advances
        Thread.sleep(forTimeInterval: 0.01)

        breaker.recordTimeout()
        guard case .open(let secondExpiry) = breaker.currentState else {
            return XCTFail("Expected open state after second timeout")
        }

        XCTAssertGreaterThan(secondExpiry, firstExpiry,
            "Second timeout should push expiry forward, extending the cooldown")

        // Breaker should still be open (10s cooldown, we've waited ~0.01s)
        XCTAssertFalse(breaker.shouldAllow())
    }
}
