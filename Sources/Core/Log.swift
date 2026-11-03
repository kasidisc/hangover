import Foundation

/// Plain-text log, one line per event, rotated to "<name>.1" when it grows past maxBytes.
final class Logger {
    let url: URL
    private let maxBytes: Int
    private let lock = NSLock()
    private let stamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    init(url: URL, maxBytes: Int = 1_048_576) {
        self.url = url
        self.maxBytes = maxBytes
    }

    func write(_ line: String) {
        lock.lock(); defer { lock.unlock() }
        let fm = FileManager.default
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? Int, size > maxBytes {
            let old = URL(fileURLWithPath: url.path + ".1")
            try? fm.removeItem(at: old)  // the previous rotated log is the only file Hangover ever replaces
            try? fm.moveItem(at: url, to: old)
        }
        let data = Data("\(stamp.string(from: Date()))  \(line)\n".utf8)
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile()
            h.write(data)
            h.closeFile()
        } else {
            try? data.write(to: url)
        }
    }

    func tail(_ n: Int) -> [String] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return Array(text.split(separator: "\n", omittingEmptySubsequences: true).suffix(n).map(String.init))
    }
}
