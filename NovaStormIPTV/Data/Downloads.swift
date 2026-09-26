import Foundation
import Combine

enum DownloadStatus: String, Codable { case downloading, done, failed }

/// A movie saved (or being saved) to the device for offline / later play.
struct DownloadItem: Identifiable, Codable, Hashable {
    let id: String          // movie streamId, as text
    var title: String
    var poster: String
    var container: String
    var url: String         // the source stream URL it was pulled from
    var fileName: String    // file under the downloads dir
    var status: DownloadStatus
    var bytes: Int64
    var total: Int64
    var message: String = ""   // shown on .failed (e.g. out of space)

    var percent: Int { total > 0 ? Int(min(100, max(0, bytes * 100 / total))) : 0 }
}

/**
 * Downloaded movies. Each movie is pulled to app-private storage as its raw file (AVPlayer
 * plays local MP4/M4V/MOV directly). A small JSON registry tracks them so they survive
 * restarts and can be listed offline. The published `items` map drives the UI.
 *
 * Uses a delegate-driven `URLSessionDownloadTask`: it streams efficiently, reports byte
 * progress, and hands back resume data on a network fault so a flaky VOD can pick up where
 * it left off instead of starting over.
 */
@MainActor
final class Downloads: NSObject, ObservableObject {
    static let shared = Downloads()

    /// Keyed by movie id. Views observe this.
    @Published private(set) var items: [String: DownloadItem] = [:]

    private var tasks: [String: URLSessionDownloadTask] = [:]   // id -> live task
    private var idByTask: [Int: String] = [:]                   // task id -> movie id
    private var finished: Set<Int> = []                         // task ids already moved on success
    private var attempts: [String: Int] = [:]                   // consecutive stalled retries
    private var lastBytes: [String: Int64] = [:]                // to detect progress between retries

    /// Give up only after this many retries make NO new bytes; a large, flaky stream that
    /// keeps inching forward is retried as long as it progresses.
    private static let maxStalls = 8
    /// Keep this much headroom so a download never fills the device.
    private static let margin: Int64 = 600 * 1024 * 1024

    private lazy var session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 60
        cfg.timeoutIntervalForResource = 6 * 60 * 60
        cfg.waitsForConnectivity = true
        return URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
    }()

    private override init() {
        super.init()
        load()
    }

    // MARK: - Storage

    nonisolated static func downloadsDir() -> URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let d = base.appendingPathComponent("downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    private static func registryURL() -> URL {
        downloadsDir().appendingPathComponent("registry.json")
    }

    nonisolated static func availableBytes() -> Int64 {
        let v = try? downloadsDir().resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return v?.volumeAvailableCapacityForImportantUsage ?? Int64.max
    }

    private static func fileSize(_ url: URL) -> Int64 {
        let n = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? NSNumber
        return n?.int64Value ?? 0
    }

    private static func gb(_ bytes: Int64) -> String {
        String(format: "%.1f GB", Double(bytes) / 1_000_000_000.0)
    }

    // MARK: - Registry

    private func load() {
        guard let data = try? Data(contentsOf: Self.registryURL()),
              let list = try? JSONDecoder().decode([DownloadItem].self, from: data) else { return }
        for var d in list {
            // A download that was mid-flight when the app died never finished.
            if d.status == .downloading {
                let f = Self.downloadsDir().appendingPathComponent(d.fileName)
                let complete = FileManager.default.fileExists(atPath: f.path) &&
                    d.total > 0 && Self.fileSize(f) == d.total
                if !complete { d.status = .failed; d.message = "Interrupted. Tap to retry." }
            }
            items[d.id] = d
        }
    }

    private func persist() {
        let list = Array(items.values)
        guard let data = try? JSONEncoder().encode(list) else { return }
        try? data.write(to: Self.registryURL(), options: .atomic)
    }

    // MARK: - Queries

    func localURL(_ id: String) -> URL? {
        guard let it = items[id], it.status == .done else { return nil }
        let f = Self.downloadsDir().appendingPathComponent(it.fileName)
        return (FileManager.default.fileExists(atPath: f.path) && Self.fileSize(f) > 0) ? f : nil
    }

    func isDownloaded(_ id: String) -> Bool { localURL(id) != nil }

    /// Movies whose source can be played back from a local file (AVPlayer can't open MKV/AVI).
    static func canDownload(container: String) -> Bool { !XtreamClient.needsRemux(container: container) }

    var completed: [DownloadItem] {
        items.values.filter { $0.status == .done }.sorted { $0.title < $1.title }
    }

    // MARK: - Start / retry

    /// Start (or restart a failed) download. No-op if already downloading or done.
    func start(id: String, title: String, poster: String, container: String, url: String) {
        if tasks[id] != nil { return }
        if isDownloaded(id) { return }
        let fileName = "\(id).\(container.isBlank ? "mp4" : container)"
        items[id] = DownloadItem(id: id, title: title, poster: poster, container: container,
                                 url: url, fileName: fileName, status: .downloading, bytes: 0, total: 0)
        attempts[id] = 0
        lastBytes[id] = 0
        persist()
        Task { [weak self] in
            guard let self else { return }
            let need = await self.probeSize(url)
            let free = Self.availableBytes()
            if need > 0 && need + Self.margin > free {
                self.fail(id, "Not enough space: needs \(Self.gb(need)), only \(Self.gb(free)) free. Free up space or delete other downloads.")
                return
            }
            self.launch(id: id, url: url, resume: nil)
        }
    }

    private func launch(id: String, url: String, resume: Data?) {
        guard let u = URL(string: url) else { fail(id, "Bad stream URL."); return }
        let task: URLSessionDownloadTask
        if let rd = resume {
            task = session.downloadTask(withResumeData: rd)
        } else {
            var req = URLRequest(url: u)
            req.setValue("NovaStorm IPTV iOS", forHTTPHeaderField: "User-Agent")
            task = session.downloadTask(with: req)
        }
        tasks[id] = task
        idByTask[task.taskIdentifier] = id
        task.resume()
    }

    private nonisolated func probeSize(_ url: String) async -> Int64 {
        guard let u = URL(string: url) else { return -1 }
        var req = URLRequest(url: u)
        req.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        req.setValue("NovaStorm IPTV iOS", forHTTPHeaderField: "User-Agent")
        guard let (_, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse else { return -1 }
        if let cr = http.value(forHTTPHeaderField: "Content-Range"),
           let tail = cr.split(separator: "/").last, let n = Int64(tail) { return n }
        let len = http.expectedContentLength
        return len > 0 ? len : -1
    }

    // MARK: - Cancel / delete

    /// Remove a download (cancels if running) and delete its file.
    func delete(_ id: String) {
        if let t = tasks[id] { idByTask.removeValue(forKey: t.taskIdentifier); t.cancel() }
        tasks.removeValue(forKey: id)
        if let it = items[id] {
            try? FileManager.default.removeItem(at: Self.downloadsDir().appendingPathComponent(it.fileName))
        }
        items.removeValue(forKey: id)
        attempts[id] = nil
        lastBytes[id] = nil
        persist()
    }

    // MARK: - Delegate hand-offs (main actor)

    private func fail(_ id: String, _ message: String) {
        guard var d = items[id] else { return }
        d.status = .failed
        d.message = message
        items[id] = d
        tasks.removeValue(forKey: id)
        persist()
    }

    fileprivate func onProgress(taskId: Int, written: Int64, total: Int64) {
        guard let id = idByTask[taskId], var d = items[id] else { return }
        d.bytes = written
        if total > 0 { d.total = total }
        d.status = .downloading
        items[id] = d
        if written > (lastBytes[id] ?? 0) { attempts[id] = 0; lastBytes[id] = written }
    }

    fileprivate func onFinishOK(taskId: Int, bytes: Int64) {
        finished.insert(taskId)
        guard let id = idByTask[taskId], var d = items[id] else { return }
        d.bytes = bytes
        d.total = bytes
        d.status = .done
        d.message = ""
        items[id] = d
        tasks.removeValue(forKey: id)
        idByTask.removeValue(forKey: taskId)
        attempts[id] = nil
        lastBytes[id] = nil
        persist()
    }

    fileprivate func onComplete(taskId: Int, error: Error?, resume: Data?) {
        // Success path already handled in onFinishOK; ignore the paired nil-error callback.
        if error == nil || finished.remove(taskId) != nil {
            idByTask.removeValue(forKey: taskId)
            return
        }
        guard let id = idByTask[taskId] else { return }
        idByTask.removeValue(forKey: taskId)
        tasks.removeValue(forKey: id)
        // Cancelled by delete() -> the item is already gone.
        guard items[id] != nil else { return }

        let n = (attempts[id] ?? 0) + 1
        attempts[id] = n
        if n > Self.maxStalls {
            let ns = error as? NSError
            let outOfSpace = Self.availableBytes() < Self.margin ||
                (ns?.localizedDescription.localizedCaseInsensitiveContains("space") ?? false)
            fail(id, outOfSpace
                 ? "Ran out of space. Free up storage or delete other downloads, then retry."
                 : "Download failed. Check your connection and retry.")
            return
        }
        // Back off, then resume where we left off if the server gave us resume data.
        let delay = Double(min(5, max(1, n)))
        let u = items[id]!.url
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self, self.items[id]?.status == .downloading else { return }
            self.launch(id: id, url: u, resume: resume)
        }
    }
}

// MARK: - URLSessionDownloadDelegate

extension Downloads: URLSessionDownloadDelegate {
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                                totalBytesExpectedToWrite: Int64) {
        let tid = downloadTask.taskIdentifier
        Task { @MainActor [weak self] in
            self?.onProgress(taskId: tid, written: totalBytesWritten, total: totalBytesExpectedToWrite)
        }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                didFinishDownloadingTo location: URL) {
        // The temp file is removed once this returns, so move it synchronously here. The
        // destination name is derived from the request URL (".../<streamId>.<container>").
        guard let src = downloadTask.originalRequest?.url ?? downloadTask.currentRequest?.url else { return }
        let dst = Downloads.downloadsDir().appendingPathComponent(src.lastPathComponent)
        let fm = FileManager.default
        try? fm.removeItem(at: dst)
        do { try fm.moveItem(at: location, to: dst) }
        catch { try? fm.copyItem(at: location, to: dst) }
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var d = dst
        try? d.setResourceValues(values)
        let size = ((try? fm.attributesOfItem(atPath: dst.path)[.size]) as? NSNumber)?.int64Value ?? 0
        let tid = downloadTask.taskIdentifier
        Task { @MainActor [weak self] in self?.onFinishOK(taskId: tid, bytes: size) }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let tid = task.taskIdentifier
        let resume = (error as? NSError)?.userInfo[NSURLSessionDownloadTaskResumeData] as? Data
        Task { @MainActor [weak self] in self?.onComplete(taskId: tid, error: error, resume: resume) }
    }
}
