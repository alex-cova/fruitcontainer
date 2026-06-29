import Foundation
import Combine
import ServiceManagement

@MainActor
final class LoginLaunchController: ObservableObject {
    static let shared = LoginLaunchController()

    @Published private(set) var openAtLoginStatus: SMAppService.Status

    private let service: SMAppService

    private init() {
        service = .mainApp
        openAtLoginStatus = service.status
    }

    var isOpenAtLoginEnabled: Bool {
        switch openAtLoginStatus {
        case .enabled, .requiresApproval:
            true
        case .notRegistered, .notFound:
            false
        @unknown default:
            false
        }
    }

    var needsApproval: Bool {
        openAtLoginStatus == .requiresApproval
    }

    func refreshStatus() {
        openAtLoginStatus = service.status
    }

    func setOpenAtLoginEnabled(_ isEnabled: Bool) throws {
        switch (isEnabled, openAtLoginStatus) {
        case (true, .enabled), (true, .requiresApproval), (false, .notRegistered), (false, .notFound):
            return
        case (true, _):
            try service.register()
        case (false, _):
            try service.unregister()
        }

        refreshStatus()
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
