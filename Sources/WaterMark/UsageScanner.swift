import Foundation

/// Token counts pulled from one or more assistant turns.
struct TokenTotals {
    var input = 0
    var output = 0
    var cacheCreation = 0
    var cacheRead = 0

    /// Tokens that represent fresh compute (what the water estimate is based on).
    /// Cache *reads* are excluded: they are cheap retrieval, not recomputation.
    var effective: Int { input + output + cacheCreation }

    /// Everything, including cache reads.
    var total: Int { input + output + cacheCreation + cacheRead }

    mutating func add(_ o: TokenTotals) {
        input += o.input
        output += o.output
        cacheCreation += o.cacheCreation
        cacheRead += o.cacheRead
    }
}

/// Usage rolled up by local calendar day, then by model.
struct UsageAggregate {
    // day ("yyyy-MM-dd") -> model id -> token totals
    var byDayModel: [String: [String: TokenTotals]] = [:]

    mutating func add(day: String, model: String, _ t: TokenTotals) {
        byDayModel[day, default: [:]][model, default: TokenTotals()].add(t)
    }

    mutating func merge(_ o: UsageAggregate) {
        for (day, models) in o.byDayModel {
            for (model, t) in models {
                byDayModel[day, default: [:]][model, default: TokenTotals()].add(t)
            }
        }
    }
}

/// Scans ~/.claude/projects/**/*.jsonl and aggregates token usage.
///
/// Only ever touched from a single serial queue (see AppDelegate.scanQueue),
/// so the per-file cache below needs no extra synchronisation.
final class UsageScanner {
    let projectsDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/projects")

    private var cache: [String: (mtime: Date, size: Int, agg: UsageAggregate)] = [:]

    static let dayFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        return f
    }()

    private static let isoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static func localDay(fromISO s: String?) -> String {
        guard let s else { return "unknown" }
        guard let date = isoFrac.date(from: s) ?? iso.date(from: s) else { return "unknown" }
        return dayFmt.string(from: date)
    }

    /// Walk every transcript, reusing cached results for files that haven't changed.
    func scan() -> UsageAggregate {
        let fm = FileManager.default
        guard let en = fm.enumerator(
            at: projectsDir,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return UsageAggregate() }

        var present = Set<String>()
        var total = UsageAggregate()

        for case let url as URL in en {
            guard url.pathExtension == "jsonl" else { continue }
            let path = url.path
            present.insert(path)

            let rv = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            let mtime = rv?.contentModificationDate ?? .distantPast
            let size = rv?.fileSize ?? -1

            if let c = cache[path], c.mtime == mtime, c.size == size {
                total.merge(c.agg)
            } else {
                let agg = parseFile(url)
                cache[path] = (mtime, size, agg)
                total.merge(agg)
            }
        }

        // Forget files that have been deleted.
        for k in cache.keys where !present.contains(k) { cache[k] = nil }

        return total
    }

    private func parseFile(_ url: URL) -> UsageAggregate {
        var agg = UsageAggregate()
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else { return agg }

        var seenIDs = Set<String>()  // dedupe streamed/repeated assistant messages

        text.enumerateLines { line, _ in
            guard !line.isEmpty,
                  let ld = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: ld) as? [String: Any],
                  let message = obj["message"] as? [String: Any],
                  let usage = message["usage"] as? [String: Any]
            else { return }

            let model = (message["model"] as? String) ?? "unknown"
            if model == "<synthetic>" { return }

            if let id = message["id"] as? String {
                if seenIDs.contains(id) { return }
                seenIDs.insert(id)
            }

            var t = TokenTotals()
            t.input = (usage["input_tokens"] as? Int) ?? 0
            t.output = (usage["output_tokens"] as? Int) ?? 0
            t.cacheCreation = (usage["cache_creation_input_tokens"] as? Int) ?? 0
            t.cacheRead = (usage["cache_read_input_tokens"] as? Int) ?? 0

            let day = Self.localDay(fromISO: obj["timestamp"] as? String)
            agg.add(day: day, model: model, t)
        }

        return agg
    }
}
