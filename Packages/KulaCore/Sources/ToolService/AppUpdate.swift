import AppKit
import CryptoKit
import Foundation
import Contracts

/// A published GitHub release that carries an installable Asky ZIP.
public struct AppRelease: Sendable, Equatable {
    public let version: String
    public let name: String
    public let pageURL: URL
    public let archiveURL: URL
    public let checksumURL: URL?
}

/// A verified release extracted beside the installed app, waiting for the swap helper.
public struct StagedAppUpdate: Sendable, Equatable {
    public let release: AppRelease
    let installed: URL
    let app: URL
    let work: URL
}

public enum AppUpdateError: LocalizedError, Equatable {
    case network(String)
    case noRelease
    case missingArchive
    case checksumMismatch
    case invalidBundle
    case translocated
    case notWritable(String)
    case installFailed(String)

    public var errorDescription: String? {
        switch self {
        case .network(let detail):
            String(format: CoreLocalization.text("无法连接 GitHub：%@"), detail)
        case .noRelease: CoreLocalization.text("GitHub 上还没有可用的发布版本。")
        case .missingArchive: CoreLocalization.text("最新发布版本中没有适用于 macOS 的安装包。")
        case .checksumMismatch: CoreLocalization.text("安装包校验失败，已停止安装。")
        case .invalidBundle: CoreLocalization.text("安装包中没有有效的 Asky.app。")
        case .translocated: CoreLocalization.text("请先将 Asky.app 移到“应用程序”文件夹并重新打开，再安装更新。")
        case .notWritable(let path):
            String(format: CoreLocalization.text("没有权限写入 %@，无法替换旧版本。"), path)
        case .installFailed(let detail):
            String(format: CoreLocalization.text("安装失败：%@"), detail)
        }
    }
}

enum AppUpdate {
    static let repository = "Niall-Young/Asky"
    static let latestReleaseURL = URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!
    static let latestPageURL = URL(string: "https://github.com/\(repository)/releases/latest")!

    /// Only use download links for this repository and this release, excluding source archives.
    static func parseWebRelease(pageURL: URL, assetsHTML: Data) throws -> AppRelease {
        let tag = try releaseTag(from: pageURL)
        let prefix = "/\(repository)/releases/download/\(tag)/"
        let html = String(decoding: assetsHTML, as: UTF8.self)
        let expression = try NSRegularExpression(pattern: #"href=["']([^"']+)["']"#)
        let links = expression.matches(in: html, range: NSRange(html.startIndex..., in: html)).compactMap { match -> URL? in
            guard let range = Range(match.range(at: 1), in: html),
                  let url = URL(string: String(html[range]), relativeTo: latestPageURL)?.absoluteURL,
                  url.scheme == "https", url.host == "github.com", url.query == nil, url.fragment == nil,
                  url.path.hasPrefix(prefix) else { return nil }
            return url
        }
        let zips = links.filter { $0.lastPathComponent.lowercased().hasSuffix(".zip") }
        guard let archive = zips.first(where: { $0.lastPathComponent.lowercased().contains("macos") }) ?? zips.first else {
            throw AppUpdateError.missingArchive
        }
        let checksum = links.first { $0.lastPathComponent == archive.lastPathComponent + ".sha256" }
        return AppRelease(version: normalizedVersion(tag), name: "Asky \(normalizedVersion(tag))",
                          pageURL: pageURL, archiveURL: archive, checksumURL: checksum)
    }

    static func releaseTag(from pageURL: URL) throws -> String {
        let prefix = "/\(repository)/releases/tag/"
        guard pageURL.scheme == "https", pageURL.host == "github.com", pageURL.path.hasPrefix(prefix) else {
            throw AppUpdateError.noRelease
        }
        let tag = String(pageURL.path.dropFirst(prefix.count))
        guard !tag.isEmpty, !tag.contains("/") else { throw AppUpdateError.noRelease }
        return tag
    }

    private struct ReleasePayload: Decodable {
        struct Asset: Decodable {
            let name: String
            let browser_download_url: URL
        }
        let tag_name: String
        let name: String?
        let html_url: URL
        let draft: Bool?
        let prerelease: Bool?
        let assets: [Asset]
    }

    /// Prefers the arm64 macOS ZIP published by the release workflow, falling back to any ZIP.
    static func parseRelease(_ data: Data) throws -> AppRelease {
        let payload = try JSONDecoder().decode(ReleasePayload.self, from: data)
        let zips = payload.assets.filter { $0.name.lowercased().hasSuffix(".zip") }
        guard let archive = zips.first(where: { $0.name.lowercased().contains("macos") }) ?? zips.first else {
            throw AppUpdateError.missingArchive
        }
        let checksum = payload.assets.first { $0.name == archive.name + ".sha256" }
        let version = normalizedVersion(payload.tag_name)
        return AppRelease(version: version, name: payload.name ?? payload.tag_name, pageURL: payload.html_url,
                          archiveURL: archive.browser_download_url, checksumURL: checksum?.browser_download_url)
    }

    static func normalizedVersion(_ tag: String) -> String {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.first == "v" || trimmed.first == "V" ? String(trimmed.dropFirst()) : trimmed
    }

    /// Numeric component comparison so "0.0.10" > "0.0.9" and "1.0" == "1.0.0".
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let parse = { (s: String) -> [Int] in normalizedVersion(s).split(separator: ".").map { Int($0) ?? 0 } }
        let a = parse(candidate), b = parse(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// `shasum -a 256` format: "<hex>  <file name>".
    static func parseChecksum(_ text: String) -> String? {
        guard let hex = text.split(whereSeparator: \.isWhitespace).first.map(String.init)?.lowercased(),
              hex.count == 64, hex.allSatisfy(\.isHexDigit) else { return nil }
        return hex
    }

    static func sha256(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// One known directory, so leftovers from an interrupted update can be found and removed.
    static func stagingRoot() throws -> URL {
        try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appending(path: Bundle.main.bundleIdentifier ?? "app.kulahere.KulaHere").appending(path: "Updates")
    }

    static func request(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: 30)
        if url.host == "api.github.com" {
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        }
        request.setValue("Asky-Updater", forHTTPHeaderField: "User-Agent")
        return request
    }

    static func run(_ executable: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(filePath: executable)
        process.arguments = arguments
        let errors = Pipe()
        process.standardError = errors
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        let data = try errors.fileHandleForReading.readToEnd() ?? Data()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let detail = String(data: data, encoding: .utf8) ?? ""
            throw AppUpdateError.installFailed(detail.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    static func runStageCommand(_ executable: String, _ arguments: [String]) async throws {
        let result = try await PluginProcess.command(executable, arguments, seconds: 300)
        guard result.exitCode == 0 else { throw AppUpdateError.installFailed(result.stderr) }
    }

    static let lsregister = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

    /// Waits for the running app to exit, swaps bundles, deletes the old one and relaunches unless
    /// `$5` is 0. On a failed move the old bundle is restored so the user is never left without an app.
    /// Hang-up and terminate are ignored so a logout cannot interrupt the two renames midway.
    static let swapScript = """
    trap '' HUP TERM
    pid="$1"; old="$2"; new="$3"; work="$4"; relaunch="${5:-1}"
    while kill -0 "$pid" 2>/dev/null; do sleep 0.2; done
    backup="$work/previous.app"
    if mv "$old" "$backup"; then
      if mv "$new" "$old"; then rm -rf "$backup"; else mv "$backup" "$old"; fi
    fi
    # Same path, new bundle: refresh Launch Services before opening, or its stale record can make it
    # launch another registered copy of a newer version, and the Dock keeps the cached old icon.
    touch "$old"
    \(lsregister) -f "$old" 2>/dev/null || true
    if [ "$relaunch" = 1 ]; then open -g "$old"; fi
    rm -rf "$work"
    """
}

/// Remember the API cooldown so repeated checks use the public Release page directly.
actor AppReleaseLookup {
    static let shared = AppReleaseLookup()
    private var apiRetryAt = Date.distantPast
    typealias Fetch = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    func latest(fetch: Fetch = { try await URLSession.shared.data(for: $0) }) async throws -> AppRelease {
        if Date() >= apiRetryAt {
            let (data, response) = try await fetch(AppUpdate.request(AppUpdate.latestReleaseURL))
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 403 || status == 429 {
                let http = response as? HTTPURLResponse
                let reset = http?.value(forHTTPHeaderField: "x-ratelimit-reset").flatMap(Double.init).map(Date.init(timeIntervalSince1970:))
                let retry = http?.value(forHTTPHeaderField: "retry-after").flatMap(Double.init) ?? 60
                apiRetryAt = max(reset ?? .distantPast, Date().addingTimeInterval(max(60, retry)))
            } else {
                if status == 404 { throw AppUpdateError.noRelease }
                guard (200..<300).contains(status) else { throw AppUpdateError.network("HTTP \(status)") }
                return try AppUpdate.parseRelease(data)
            }
        }
        let (_, pageResponse) = try await fetch(AppUpdate.request(AppUpdate.latestPageURL))
        let status = (pageResponse as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 { throw AppUpdateError.noRelease }
        guard (200..<300).contains(status) else { throw AppUpdateError.network("HTTP \(status)") }
        guard let pageURL = pageResponse.url else { throw AppUpdateError.noRelease }
        _ = try AppUpdate.releaseTag(from: pageURL)
        let assetsURL = URL(string: pageURL.absoluteString.replacingOccurrences(of: "/releases/tag/", with: "/releases/expanded_assets/"))!
        let (assets, assetsResponse) = try await fetch(AppUpdate.request(assetsURL))
        let assetsStatus = (assetsResponse as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(assetsStatus) else { throw AppUpdateError.network("HTTP \(assetsStatus)") }
        return try AppUpdate.parseWebRelease(pageURL: pageURL, assetsHTML: assets)
    }
}

extension ToolService {
    public static var currentAppVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    public static var currentAppBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
    }

    public static var appRepositoryURL: URL { URL(string: "https://github.com/\(AppUpdate.repository)")! }

    /// Returns the latest release only when it is newer than the running app.
    public static func checkForAppUpdate() async throws -> AppRelease? {
        let release: AppRelease
        do { release = try await AppReleaseLookup.shared.latest() }
        catch let error as AppUpdateError { throw error }
        catch { throw AppUpdateError.network(error.localizedDescription) }
        return AppUpdate.isNewer(release.version, than: currentAppVersion) ? release : nil
    }

    /// Downloads, verifies and extracts the release next to the installed app without touching it.
    public static func stageAppUpdate(_ release: AppRelease, progress: @escaping @Sendable (String) async -> Void = { _ in }) async throws -> StagedAppUpdate {
        let installed = Bundle.main.bundleURL.standardizedFileURL
        guard !installed.path.contains("/AppTranslocation/") else { throw AppUpdateError.translocated }
        let parent = installed.deletingLastPathComponent()
        let fileManager = FileManager.default
        guard fileManager.isWritableFile(atPath: parent.path), fileManager.isWritableFile(atPath: installed.path) else {
            throw AppUpdateError.notWritable(parent.path)
        }
        let work = try AppUpdate.stagingRoot().appending(path: UUID().uuidString)
        try fileManager.createDirectory(at: work, withIntermediateDirectories: true)
        do {
            await progress(CoreLocalization.text("正在下载…"))
            let archive = work.appending(path: release.archiveURL.lastPathComponent)
            do {
                let (downloaded, response) = try await URLSession.shared.download(for: AppUpdate.request(release.archiveURL))
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                    throw AppUpdateError.network("HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
                }
                try fileManager.moveItem(at: downloaded, to: archive)
            } catch let error as AppUpdateError { throw error }
            catch { throw AppUpdateError.network(error.localizedDescription) }

            await progress(CoreLocalization.text("正在校验…"))
            guard let checksumURL = release.checksumURL else { throw AppUpdateError.checksumMismatch }
            do {
                let (data, _) = try await URLSession.shared.data(for: AppUpdate.request(checksumURL))
                guard let expected = AppUpdate.parseChecksum(String(decoding: data, as: UTF8.self)),
                      try AppUpdate.sha256(of: archive) == expected else { throw AppUpdateError.checksumMismatch }
            }

            await progress(CoreLocalization.text("正在安装…"))
            let extracted = work.appending(path: "extracted")
            try await AppUpdate.runStageCommand("/usr/bin/ditto", ["-x", "-k", archive.path, extracted.path])
            let candidates = (try? fileManager.contentsOfDirectory(at: extracted, includingPropertiesForKeys: nil)) ?? []
            guard let app = candidates.first(where: { $0.pathExtension == "app" }),
                  let bundle = Bundle(url: app),
                  bundle.bundleIdentifier == Bundle.main.bundleIdentifier else { throw AppUpdateError.invalidBundle }
            let requirement = #"anchor apple generic and certificate leaf[subject.OU] = "V8GVW783CK" and certificate leaf[field.1.2.840.113635.100.6.1.13] exists"#
            try await AppUpdate.runStageCommand("/usr/bin/codesign", ["--verify", "--deep", "--strict", "-R=" + requirement, app.path])
            try? fileManager.removeItem(at: archive)
            return StagedAppUpdate(release: release, installed: installed, app: app, work: work)
        } catch {
            try? fileManager.removeItem(at: work)
            throw error
        }
    }

    /// Starts the detached swap helper; it waits for this process to exit before replacing the bundle.
    public static func installStagedAppUpdate(_ staged: StagedAppUpdate, relaunch: Bool) throws {
        guard FileManager.default.fileExists(atPath: staged.app.path) else { throw AppUpdateError.invalidBundle }
        let helper = Process()
        helper.executableURL = URL(filePath: "/bin/sh")
        helper.arguments = ["-c", AppUpdate.swapScript, "asky-update",
                            String(ProcessInfo.processInfo.processIdentifier), staged.installed.path,
                            staged.app.path, staged.work.path, relaunch ? "1" : "0"]
        helper.standardOutput = FileHandle.nullDevice
        helper.standardError = FileHandle.nullDevice
        do { try helper.run() } catch { throw AppUpdateError.installFailed(error.localizedDescription) }
    }

    /// Removes downloads and old bundles left behind by an interrupted update. Call once at launch,
    /// before anything is staged; a finished swap helper has already deleted its own directory.
    public static func removeStaleAppUpdates() {
        guard let root = try? AppUpdate.stagingRoot() else { return }
        try? FileManager.default.removeItem(at: root)
    }

    public static func discardStagedAppUpdate(_ staged: StagedAppUpdate) {
        try? FileManager.default.removeItem(at: staged.work)
    }
}
