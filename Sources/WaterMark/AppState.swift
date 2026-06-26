import SwiftUI
import ServiceManagement

/// Which usage window the UI / menu-bar figure reflects.
enum BarWindow: String, CaseIterable, Identifiable {
    case today, week, month, all
    var id: String { rawValue }
    var title: String {
        switch self {
        case .today: return "Today"
        case .week:  return "7 Days"
        case .month: return "30 Days"
        case .all:   return "All Time"
        }
    }
}

/// Observable bridge between the scanner/water model and the SwiftUI views.
@MainActor
final class AppState: ObservableObject {
    @Published var aggregate = UsageAggregate()
    @Published var barWindow: BarWindow {
        didSet { UserDefaults.standard.set(barWindow.rawValue, forKey: "barWindow") }
    }
    /// Bumped whenever a rate changes so views re-render (rates live in UserDefaults).
    @Published private(set) var ratesTick = 0

    let water = WaterModel()
    var refreshHandler: (() -> Void)?

    init() {
        barWindow = BarWindow(rawValue: UserDefaults.standard.string(forKey: "barWindow") ?? "") ?? .today
    }

    // MARK: - Windows

    private static func dayKey(_ d: Date) -> String { UsageScanner.dayFmt.string(from: d) }

    private static func lastNDays(_ n: Int) -> [String] {
        let cal = Calendar.current
        let now = Date()
        return (0..<n).compactMap { cal.date(byAdding: .day, value: -$0, to: now) }.map { dayKey($0) }
    }

    private func dayKeys(for w: BarWindow) -> [String]? {
        switch w {
        case .today: return [Self.dayKey(Date())]
        case .week:  return Self.lastNDays(7)
        case .month: return Self.lastNDays(30)
        case .all:   return nil
        }
    }

    func tokens(for w: BarWindow) -> [String: TokenTotals] {
        let filter = dayKeys(for: w).map(Set.init)
        var out: [String: TokenTotals] = [:]
        for (day, models) in aggregate.byDayModel {
            if let filter, !filter.contains(day) { continue }
            for (m, t) in models { out[m, default: TokenTotals()].add(t) }
        }
        return out
    }

    func waterML(for w: BarWindow) -> Double {
        tokens(for: w).reduce(0.0) { $0 + water.water(forModel: $1.key, tokens: $1.value.effective) }
    }

    func effectiveTokens(for w: BarWindow) -> Int {
        tokens(for: w).values.reduce(0) { $0 + $1.effective }
    }

    /// Per-model rows for a window, sorted by water descending.
    func perModel(for w: BarWindow) -> [(model: String, tokens: Int, ml: Double)] {
        tokens(for: w)
            .map { (model: $0.key, tokens: $0.value.effective,
                    ml: water.water(forModel: $0.key, tokens: $0.value.effective)) }
            .sorted { $0.ml > $1.ml }
    }

    /// Daily water (mL) for the last `n` days, oldest first — for the trend chart.
    func dailySeries(_ n: Int) -> [Double] {
        let cal = Calendar.current
        let now = Date()
        return (0..<n).reversed().map { offset in
            guard let d = cal.date(byAdding: .day, value: -offset, to: now) else { return 0 }
            let models = aggregate.byDayModel[Self.dayKey(d)] ?? [:]
            return models.reduce(0.0) { $0 + water.water(forModel: $1.key, tokens: $1.value.effective) }
        }
    }

    /// Every model ever seen (for the settings rate list).
    var allModels: [String] {
        var set = Set<String>()
        for (_, models) in aggregate.byDayModel { set.formUnion(models.keys) }
        return set.sorted()
    }

    // MARK: - Rates

    func rate(for model: String) -> Double { water.rate(for: model) }
    func defaultRate(for model: String) -> Double { water.defaultRate(for: model) }
    func setRate(_ v: Double, for model: String) { water.setRate(max(0, v), for: model); ratesTick += 1 }
    func resetRate(for model: String) { water.resetRate(for: model); ratesTick += 1 }

    // MARK: - Launch at login

    var launchAtLogin: Bool { SMAppService.mainApp.status == .enabled }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("WaterMark: launch-at-login toggle failed: \(error)")
        }
        objectWillChange.send()
    }

    func refresh() { refreshHandler?() }

    // MARK: - Formatting

    static func fmtWater(_ ml: Double) -> String {
        if ml >= 1000 { return String(format: "%.2f L", ml / 1000) }
        if ml >= 10 { return String(format: "%.0f mL", ml) }
        return String(format: "%.1f mL", ml)
    }

    static func fmtTokens(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    /// Compact token count for tight spaces, e.g. "13.8M".
    static func fmtTokensCompact(_ n: Int) -> String {
        let d = Double(n)
        if d >= 1_000_000 { return String(format: "%.1fM", d / 1_000_000) }
        if d >= 1_000 { return String(format: "%.1fK", d / 1_000) }
        return "\(n)"
    }

    static func prettyModel(_ m: String) -> String {
        m.replacingOccurrences(of: "claude-", with: "")
    }
}
