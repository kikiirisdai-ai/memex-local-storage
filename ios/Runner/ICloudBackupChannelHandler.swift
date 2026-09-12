import Flutter
import Foundation
import UIKit
import UniformTypeIdentifiers

/// Handles the iOS side of `com.memexlab.memex/backup_storage`:
/// user-picked iCloud Drive folder via UIDocumentPicker + persisted
/// security-scoped bookmark, so daily backups land OUTSIDE the app sandbox
/// (survive uninstall). Bookmark stored in UserDefaults; never requires the
/// iCloud entitlement (verified on the free-provisioned build).
class ICloudBackupChannelHandler: NSObject, UIDocumentPickerDelegate {
    private static let bookmarkKey = "icloud_backup_bookmark_v1"
    private static let displayNameKey = "icloud_backup_display_name_v1"
    private var pendingPickResult: FlutterResult?

    static func register(with messenger: FlutterBinaryMessenger) {
        let channel = FlutterMethodChannel(
            name: "com.memexlab.memex/backup_storage",
            binaryMessenger: messenger
        )
        let instance = ICloudBackupChannelHandler()
        channel.setMethodCallHandler { call, result in instance.handle(call, result: result) }
    }

    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]
        switch call.method {
        case "icloudPickFolder":    pickFolder(result: result)
        case "icloudFolderStatus":  result(folderStatus())
        case "icloudWriteFile":     writeFile(args, result: result)
        case "icloudReadFileToTemp": readFileToTemp(args, result: result)
        case "icloudRenameFile":    renameFile(args, result: result)
        case "icloudDeleteFile":    deleteFile(args, result: result)
        case "icloudListFiles":     result(["files": listFiles()])
        case "icloudUploadStatus":  uploadStatus(result: result)
        case "icloudClearFolder":
            UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
            UserDefaults.standard.removeObject(forKey: Self.displayNameKey)
            result(["cleared": true])
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: pick
    private func pickFolder(result: @escaping FlutterResult) {
        guard let root = Self.topViewController() else {
            result(FlutterError(code: "no_vc", message: "No root VC", details: nil)); return
        }
        pendingPickResult = result
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.folder], asCopy: false)
        picker.delegate = self
        picker.allowsMultipleSelection = false
        root.present(picker, animated: true)
    }
    func documentPicker(_ c: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        let r = pendingPickResult; pendingPickResult = nil
        guard let url = urls.first else { r?(FlutterError(code: "no_url", message: "none", details: nil)); return }
        let ok = url.startAccessingSecurityScopedResource()
        defer { if ok { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(data, forKey: Self.bookmarkKey)
            UserDefaults.standard.set(url.lastPathComponent, forKey: Self.displayNameKey)
            r?(["path": url.path, "displayName": url.lastPathComponent])
        } catch {
            r?(FlutterError(code: "bookmark_failed", message: error.localizedDescription, details: nil))
        }
    }
    func documentPickerWasCancelled(_ c: UIDocumentPickerViewController) {
        let r = pendingPickResult; pendingPickResult = nil
        r?(FlutterError(code: "cancelled", message: "cancelled", details: nil))
    }

    // MARK: resolve helper
    private func resolvedURL() -> (URL, Bool)? {
        guard let data = UserDefaults.standard.data(forKey: Self.bookmarkKey) else { return nil }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale) else { return nil }
        return (url, isStale)
    }

    private func folderStatus() -> [String: Any] {
        guard let (url, isStale) = resolvedURL() else { return ["configured": false, "isStale": false] }
        return ["configured": true,
                "displayName": UserDefaults.standard.string(forKey: Self.displayNameKey) ?? url.lastPathComponent,
                "path": url.path, "isStale": isStale]
    }

    private func writeFile(_ args: [String: Any], result: @escaping FlutterResult) {
        guard let src = args["sourcePath"] as? String, let name = args["fileName"] as? String else {
            result(FlutterError(code: "bad_args", message: "sourcePath/fileName", details: nil)); return
        }
        guard let (dir, isStale) = resolvedURL() else {
            result(FlutterError(code: "no_bookmark", message: "not configured", details: nil)); return
        }
        let ok = dir.startAccessingSecurityScopedResource()
        defer { if ok { dir.stopAccessingSecurityScopedResource() } }
        let dest = dir.appendingPathComponent(name)
        do {
            if FileManager.default.fileExists(atPath: dest.path) { try FileManager.default.removeItem(at: dest) }
            try FileManager.default.copyItem(at: URL(fileURLWithPath: src), to: dest)
            result(["path": dest.path, "isStale": isStale])
        } catch {
            result(FlutterError(code: "write_failed", message: error.localizedDescription, details: nil))
        }
    }

    /// Copies `fileName` out of the security-scoped iCloud folder into a
    /// temp file the caller can read with plain dart:io, since the iCloud
    /// folder itself cannot be opened outside the scoped-resource bracket.
    private func readFileToTemp(_ args: [String: Any], result: @escaping FlutterResult) {
        guard let name = args["fileName"] as? String else {
            result(FlutterError(code: "bad_args", message: "fileName", details: nil)); return
        }
        guard let (dir, _) = resolvedURL() else {
            result(FlutterError(code: "no_bookmark", message: "not configured", details: nil)); return
        }
        let ok = dir.startAccessingSecurityScopedResource()
        defer { if ok { dir.stopAccessingSecurityScopedResource() } }
        let src = dir.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: src.path) else {
            result(FlutterError(code: "not_found", message: "file not found", details: nil)); return
        }
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("icloud_read_\(UUID().uuidString)")
        let dest = tempDir.appendingPathComponent(name)
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: src, to: dest)
            result(["path": dest.path])
        } catch {
            result(FlutterError(code: "read_failed", message: error.localizedDescription, details: nil))
        }
    }

    private func renameFile(_ args: [String: Any], result: @escaping FlutterResult) {
        guard let from = args["from"] as? String, let to = args["to"] as? String,
              let (dir, _) = resolvedURL() else { result(["renamed": false]); return }
        let ok = dir.startAccessingSecurityScopedResource()
        defer { if ok { dir.stopAccessingSecurityScopedResource() } }
        let src = dir.appendingPathComponent(from), dst = dir.appendingPathComponent(to)
        guard FileManager.default.fileExists(atPath: src.path) else { result(["renamed": false]); return }
        do {
            if FileManager.default.fileExists(atPath: dst.path) { try FileManager.default.removeItem(at: dst) }
            try FileManager.default.moveItem(at: src, to: dst)
            result(["renamed": true])
        } catch { result(["renamed": false]) }
    }

    private func deleteFile(_ args: [String: Any], result: @escaping FlutterResult) {
        guard let name = args["fileName"] as? String, let (dir, _) = resolvedURL() else { result(["deleted": false]); return }
        let ok = dir.startAccessingSecurityScopedResource()
        defer { if ok { dir.stopAccessingSecurityScopedResource() } }
        let f = dir.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: f.path) {
            do { try FileManager.default.removeItem(at: f); result(["deleted": true]) } catch { result(["deleted": false]) }
        } else { result(["deleted": false]) }
    }

    private func listFiles() -> [[String: Any]] {
        guard let (dir, _) = resolvedURL() else { return [] }
        let ok = dir.startAccessingSecurityScopedResource()
        defer { if ok { dir.stopAccessingSecurityScopedResource() } }
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])) ?? []
        return urls.filter { $0.pathExtension.lowercased() == "memex" }.map { u in
            let v = try? u.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let ms = Int((v?.contentModificationDate ?? Date()).timeIntervalSince1970 * 1000)
            return ["name": u.lastPathComponent, "path": u.path,
                    "sizeBytes": v?.fileSize ?? 0, "modifiedMs": ms]
        }
    }

    private func uploadStatus(result: @escaping FlutterResult) {
        guard let (dir, _) = resolvedURL() else { result(["files": []]); return }
        let ok = dir.startAccessingSecurityScopedResource()
        defer { if ok { dir.stopAccessingSecurityScopedResource() } }
        let keys: Set<URLResourceKey> = [.ubiquitousItemIsUploadedKey, .ubiquitousItemIsUploadingKey, .ubiquitousItemUploadingErrorKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: Array(keys))) ?? []
        let files: [[String: Any]] = urls.filter { $0.pathExtension.lowercased() == "memex" }.map { u in
            let v = try? u.resourceValues(forKeys: keys)
            return ["name": u.lastPathComponent,
                    "uploaded": v?.ubiquitousItemIsUploaded ?? false,
                    "uploading": v?.ubiquitousItemIsUploading ?? false,
                    "hasError": (v?.ubiquitousItemUploadingError != nil)]
        }
        result(["files": files])
    }

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.first { $0.activationState == .foregroundActive } as? UIWindowScene
        let window = scene?.windows.first { $0.isKeyWindow } ?? scene?.windows.first
        var top = window?.rootViewController
        while let p = top?.presentedViewController { top = p }
        return top
    }
}
