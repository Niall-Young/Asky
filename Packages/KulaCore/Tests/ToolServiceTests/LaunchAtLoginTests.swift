import ServiceManagement
import Testing
@testable import ToolService

@Suite @MainActor struct LaunchAtLoginTests {
    @MainActor private final class System {
        var status: LaunchAtLoginStatus = .notRegistered
        var registrationResult: LaunchAtLoginStatus = .enabled
        var failure = false
        var registers = 0
        var unregisters = 0
        enum Failure: Error { case denied }

        var registration: LaunchAtLoginRegistration {
            LaunchAtLoginRegistration(status: { self.status }, register: {
                self.registers += 1
                if self.failure { throw Failure.denied }
                self.status = self.registrationResult
            }, unregister: {
                self.unregisters += 1
                if self.failure { throw Failure.denied }
                self.status = .notRegistered
            })
        }
    }

    @Test func preservesAllSystemStates() {
        #expect(LaunchAtLoginStatus(SMAppService.Status.enabled) == .enabled)
        #expect(LaunchAtLoginStatus(SMAppService.Status.notRegistered) == .notRegistered)
        #expect(LaunchAtLoginStatus(SMAppService.Status.requiresApproval) == .requiresApproval)
        #expect(LaunchAtLoginStatus(SMAppService.Status.notFound) == .notFound)
    }

    @Test func approvalIsNotReportedAsEnabledOrRegisteredAgain() throws {
        let system = System()
        system.registrationResult = .requiresApproval
        #expect(try system.registration.setEnabled(true) == .requiresApproval)
        #expect(try system.registration.setEnabled(true) == .requiresApproval)
        #expect(system.registers == 1)
        #expect(system.unregisters == 0)
    }

    @Test func repeatedRequestsAreIdempotent() throws {
        let system = System()
        #expect(try system.registration.setEnabled(false) == .notRegistered)
        #expect(try system.registration.setEnabled(true) == .enabled)
        #expect(try system.registration.setEnabled(true) == .enabled)
        #expect(try system.registration.setEnabled(false) == .notRegistered)
        #expect(try system.registration.setEnabled(false) == .notRegistered)
        #expect(system.registers == 1)
        #expect(system.unregisters == 1)
    }

    @Test func canCancelPendingApproval() throws {
        let system = System()
        system.status = .requiresApproval
        #expect(try system.registration.setEnabled(false) == .notRegistered)
        #expect(system.unregisters == 1)
    }

    @Test func explicitEnableCanRepairMissingRegistration() throws {
        let system = System()
        system.status = .notFound
        #expect(try system.registration.setEnabled(true) == .enabled)
        #expect(system.registers == 1)
    }

    @Test func failedEnableDoesNotIssueInverseWrite() {
        let system = System()
        system.failure = true
        #expect(throws: System.Failure.self) { try system.registration.setEnabled(true) }
        #expect(system.status == .notRegistered)
        #expect(system.registers == 1)
        #expect(system.unregisters == 0)
    }

    @Test func failedDisableKeepsActualEnabledState() {
        let system = System()
        system.status = .enabled
        system.failure = true
        #expect(throws: System.Failure.self) { try system.registration.setEnabled(false) }
        #expect(system.status == .enabled)
        #expect(system.registers == 0)
        #expect(system.unregisters == 1)
    }

    @Test(arguments: [LaunchAtLoginStatus.notRegistered, .notFound, .unknown])
    func successfulCallWithoutConfirmedRegistrationIsAnError(result: LaunchAtLoginStatus) {
        let system = System()
        system.registrationResult = result
        #expect(throws: (any Error).self) { try system.registration.setEnabled(true) }
        #expect(system.status == result)
        #expect(system.registers == 1)
        #expect(system.unregisters == 0)
    }
}
