import Foundation

public enum LoginItemStatus { case notRegistered, enabled, requiresApproval, notFound }

public protocol LoginItemService: AnyObject {
    var status: LoginItemStatus { get }
    func register() throws
    func unregister() throws
    func openSettings()
}

/// State comes from the service, never from stored app preferences.
public final class LoginItemSettingsModel {
    public static let title = "ログイン時に Scrim を開く"
    public static let approvalText = "システム設定の『ログイン項目』で許可が必要です"
    public static let settingsTitle = "システム設定を開く"
    public static let registerErrorText = "ログイン項目に登録できませんでした。システム設定の『ログイン項目』を確認してください。"
    public static let unregisterErrorText = "ログイン項目から外せませんでした。システム設定の『ログイン項目』を確認してください。"
    private let service: LoginItemService
    public private(set) var errorText: String?
    public init(service: LoginItemService) { self.service = service }
    public var isOn: Bool { service.status == .enabled || service.status == .requiresApproval }
    public var showsApproval: Bool { service.status == .requiresApproval }
    public var showsSettings: Bool { showsApproval || errorText != nil }
    public func setEnabled(_ enabled: Bool) {
        errorText = nil
        do {
            if enabled { try service.register() } else { try service.unregister() }
        } catch {
            errorText = enabled ? Self.registerErrorText : Self.unregisterErrorText
        }
    }
    public func openSettings() { service.openSettings() }
}

/// Shared by previews and tests; never touches ServiceManagement.
public final class FakeLoginItemService: LoginItemService {
    public var status: LoginItemStatus
    public var failure: Error?
    public private(set) var registerCalls = 0
    public private(set) var unregisterCalls = 0
    public private(set) var settingsCalls = 0
    public init(status: LoginItemStatus = .notRegistered) { self.status = status }
    public func register() throws {
        registerCalls += 1
        if let failure { throw failure }
        status = .enabled
    }
    public func unregister() throws {
        unregisterCalls += 1
        if let failure { throw failure }
        status = .notRegistered
    }
    public func openSettings() { settingsCalls += 1 }
}
