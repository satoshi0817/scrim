import AppKit
import CryptoKit
import SwiftUI
import UserNotifications

private struct UpdateError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

struct PublishedRelease: Decodable {
    struct Asset: Decodable {
        let name: String
        let browser_download_url: URL
        let digest: String?
    }
    let tag_name: String
    let draft: Bool
    let prerelease: Bool
    let assets: [Asset]
    var version: String { String(tag_name.drop(while: { $0 == "v" })) }
    var archive: Asset? { assets.first { $0.name == "Scrim-" + version + ".zip" } }
}

enum ReleasePackage {
    static func newer(_ offered: String, than installed: String) -> Bool {
        func parts(_ v: String) -> [Int]? {
            let fields = v.components(separatedBy: ".")
            let numbers = fields.compactMap { Int($0) }
            guard numbers.count == fields.count, numbers.allSatisfy({ $0 >= 0 }) else { return nil }
            return numbers
        }
        guard let a = parts(offered), let b = parts(installed) else { return false }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    private static func run(_ path: String, _ arguments: [String]) throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = arguments
        try task.run()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else { throw UpdateError("配布パッケージの展開または署名確認に失敗しました。") }
    }

    static func install(zip: URL, digest: String, version: String, destination: URL) throws {
        let fm = FileManager.default
        let hash = SHA256.hash(data: try Data(contentsOf: zip, options: .mappedIfSafe)).map { String(format: "%02x", $0) }.joined()
        guard digest == "sha256:" + hash else { throw UpdateError("ZIPのチェックサムが一致しません。") }
        let temp = try fm.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: destination, create: true)
        defer { try? fm.removeItem(at: temp) }
        try run("/usr/bin/ditto", ["-x", "-k", zip.path, temp.path])
        let next = temp.appendingPathComponent("Scrim.app")
        let requirement = #"anchor apple generic and identifier "com.satoshi0817.Scrim" and certificate leaf[subject.OU] = "4LPTZP2QZM" and certificate leaf[field.1.2.840.113635.100.6.1.13] exists"#
        try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", "-R=" + requirement, next.path])
        func info(_ url: URL) throws -> [String: Any] {
            let data = try Data(contentsOf: url.appendingPathComponent("Contents/Info.plist"))
            return try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] ?? [:]
        }
        let installed = try info(destination), offered = try info(next)
        guard installed["CFBundleIdentifier"] as? String == "com.satoshi0817.Scrim",
              offered["CFBundleShortVersionString"] as? String == version,
              let old = installed["CFBundleShortVersionString"] as? String, newer(version, than: old) else {
            throw UpdateError("インストール済みの版と配布版の情報を確認してください。")
        }
        #if arch(arm64)
        let cpu = NSNumber(value: CPU_TYPE_ARM64)
        #else
        let cpu = NSNumber(value: CPU_TYPE_X86_64)
        #endif
        guard Bundle(url: next)?.executableArchitectures?.contains(cpu) == true else {
            throw UpdateError("この配布版はお使いのMacのプロセッサに対応していません。")
        }
        if let minimum = offered["LSMinimumSystemVersion"] as? String {
            let os = ProcessInfo.processInfo.operatingSystemVersion
            guard !newer(minimum, than: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)") else {
                throw UpdateError("この版には macOS " + minimum + " 以降が必要です。")
            }
        }
        // The two bundles must be on the same volume. A failed swap preserves the installed app.
        guard renameatx_np(AT_FDCWD, next.path, AT_FDCWD, destination.path, UInt32(RENAME_SWAP)) == 0 else {
            throw UpdateError("アプリを置き換えられません。Scrim.app の保存場所と書き込み権限を確認してください。")
        }
    }
}

@MainActor final class ReleaseUpdater: ObservableObject {
    static let shared = ReleaseUpdater()
    nonisolated static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    nonisolated static let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    @Published private(set) var candidate: PublishedRelease?
    @Published private(set) var busy = false
    @Published private(set) var installed = false
    @Published private(set) var status = ""
    @Published var automatic = UserDefaults.standard.bool(forKey: "installReleaseUpdates") {
        didSet { UserDefaults.standard.set(automatic, forKey: "installReleaseUpdates"); if automatic { check() } }
    }
    @Published var notifications = UserDefaults.standard.bool(forKey: "notifyReleaseUpdates") {
        didSet {
            UserDefaults.standard.set(notifications, forKey: "notifyReleaseUpdates")
            if notifications {
                Task {
                    if (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert])) == true { check() }
                    else { status = "通知の許可はmacOSの通知設定で変更できます。" }
                }
            }
        }
    }
    private var timer: Timer?
    func start() {
        if automatic || notifications { check() }
        timer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { _ in
            Task { @MainActor in if self.automatic || self.notifications { self.check() } }
        }
    }
    private func notify(_ version: String) async {
        guard notifications else { return }
        let key = "lastReleaseNotice"
        guard UserDefaults.standard.string(forKey: key) != version else { return }
        let content = UNMutableNotificationContent()
        content.title = "Scrim " + version
        content.body = installed ? "インストールしました。次回の起動から利用できます。" : "設定の「一般」からアップデートできます。"
        do {
            try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "ScrimRelease", content: content, trigger: nil))
            UserDefaults.standard.set(version, forKey: key)
        } catch { status += " 通知を送信できませんでした。" }
    }
    func check() {
        guard !busy, !installed else { return }
        busy = true
        status = "アップデートを確認中…"
        Task {
            defer { busy = false }
            do {
                let url = URL(string: "https://api.github.com/repos/satoshi0817/scrim/releases/latest")!
                let (data, response) = try await URLSession.shared.data(from: url)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError("GitHubのリリースを取得できませんでした。") }
                let release = try JSONDecoder().decode(PublishedRelease.self, from: data)
                guard !release.draft, !release.prerelease, ReleasePackage.newer(release.version, than: Self.version) else {
                    candidate = nil; status = "最新の公開版です。"; return
                }
                candidate = release
                status = "バージョン " + release.version + " が利用できます。"
                if automatic { try await install(release) }
                await notify(release.version)
            } catch { status = error.localizedDescription }
        }
    }
    func installNow() {
        guard let candidate, !busy, !installed else { return }
        busy = true
        Task {
            defer { busy = false }
            do { try await install(candidate) } catch { status = error.localizedDescription }
        }
    }
    private func install(_ release: PublishedRelease) async throws {
        guard let asset = release.archive, let digest = asset.digest,
              asset.browser_download_url.absoluteString.hasPrefix("https://github.com/satoshi0817/scrim/releases/download/") else {
            throw UpdateError("署名確認に必要な配布ZIPまたはチェックサムがありません。")
        }
        status = "ダウンロード・署名確認中…"
        let (file, response) = try await URLSession.shared.download(from: asset.browser_download_url)
        defer { try? FileManager.default.removeItem(at: file) }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError("ダウンロードに失敗しました。") }
        let destination = Bundle.main.bundleURL
        try await Task.detached {
            try ReleasePackage.install(zip: file, digest: digest, version: release.version, destination: destination)
        }.value
        installed = true
        status = "インストール済みです。次回の起動から " + release.version + " を利用できます。"
    }
}

struct ReleaseSettings: View {
    @ObservedObject private var updater = ReleaseUpdater.shared
    var body: some View {
        LabeledContent("実行中のバージョン", value: ReleaseUpdater.version + " (" + ReleaseUpdater.build + ")")
        Toggle("アップデートを通知", isOn: $updater.notifications)
        Toggle("新しい公開版を自動インストール", isOn: $updater.automatic)
        HStack {
            Button("今すぐ確認") { updater.check() }
            if let release = updater.candidate, !updater.installed {
                Button(release.version + " をインストール") { updater.installNow() }
            }
        }.disabled(updater.busy || updater.installed)
        if !updater.status.isEmpty { Text(updater.status).font(.callout).foregroundStyle(.secondary) }
    }
}
