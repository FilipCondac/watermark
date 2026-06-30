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

    private func waterML(_ model: String, _ t: TokenTotals) -> Double {
        water.waterML(forModel: model, output: t.output, prefill: t.prefill)
    }

    func waterML(for w: BarWindow) -> Double {
        tokens(for: w).reduce(0.0) { $0 + waterML($1.key, $1.value) }
    }

    func effectiveTokens(for w: BarWindow) -> Int {
        tokens(for: w).values.reduce(0) { $0 + $1.effective }
    }

    /// Per-model rows for a window, sorted by water descending.
    func perModel(for w: BarWindow) -> [(model: String, tokens: Int, ml: Double)] {
        tokens(for: w)
            .map { (model: $0.key, tokens: $0.value.effective, ml: waterML($0.key, $0.value)) }
            .sorted { $0.ml > $1.ml }
    }

    /// Daily water (mL) for the last `n` days, oldest first — for the trend chart.
    func dailySeries(_ n: Int) -> [Double] {
        let cal = Calendar.current
        let now = Date()
        return (0..<n).reversed().map { offset in
            guard let d = cal.date(byAdding: .day, value: -offset, to: now) else { return 0 }
            let models = aggregate.byDayModel[Self.dayKey(d)] ?? [:]
            return models.reduce(0.0) { $0 + waterML($1.key, $1.value) }
        }
    }

    /// Every model ever seen (for the settings rate list).
    var allModels: [String] {
        var set = Set<String>()
        for (_, models) in aggregate.byDayModel { set.formUnion(models.keys) }
        return set.sorted()
    }

    // MARK: - Rates

    // MARK: - Energy coefficients (Wh / 1k tokens)

    func outWhPer1k(for model: String) -> Double { water.outWhPer1k(for: model) }
    func prefillWhPer1k(for model: String) -> Double { water.prefillWhPer1k(for: model) }
    func defaultEnergy(for model: String) -> (out: Double, prefill: Double) {
        let e = water.defaultEnergy(for: model); return (e.out, e.prefill)
    }
    func setOutWhPer1k(_ v: Double, for model: String) { water.setOutWhPer1k(v, for: model); ratesTick += 1 }
    func setPrefillWhPer1k(_ v: Double, for model: String) { water.setPrefillWhPer1k(v, for: model); ratesTick += 1 }
    func resetEnergy(for model: String) { water.resetEnergy(for: model); ratesTick += 1 }

    // MARK: - Water intensity (L/kWh)

    var wueOnsite: Double {
        get { water.wueOnsite }
        set { water.wueOnsite = newValue; ratesTick += 1 }
    }
    var wueSource: Double {
        get { water.wueSource }
        set { water.wueSource = newValue; ratesTick += 1 }
    }
    var comprehensive: Bool {
        get { water.comprehensive }
        set { water.comprehensive = newValue; ratesTick += 1 }
    }

    // MARK: - Training (amortised, estimated)

    var includeTraining: Bool {
        get { water.includeTraining }
        set { water.includeTraining = newValue; ratesTick += 1 }
    }

    /// MAU expressed in millions, for tidy editing.
    var mauMillions: Double {
        get { water.monthlyActiveUsers / 1_000_000 }
        set { water.monthlyActiveUsers = max(0, newValue) * 1_000_000; ratesTick += 1 }
    }

    var mauText: String { AppState.fmtTokensCompact(Int(water.monthlyActiveUsers)) }

    func trainingLiters(for model: String) -> Double { water.trainingLiters(for: model) }
    func defaultTrainingLiters(for model: String) -> Double { water.defaultTrainingLiters(for: model) }
    func setTrainingLiters(_ v: Double, for model: String) { water.setTrainingLiters(v, for: model); ratesTick += 1 }
    func resetTrainingLiters(for model: String) { water.resetTrainingLiters(for: model); ratesTick += 1 }

    /// Your one-time amortised training share (mL) across every model you've used.
    var lifetimeTrainingShareML: Double {
        guard includeTraining else { return 0 }
        return allModels.reduce(0.0) { $0 + water.trainingShareML(for: $1) }
    }

    /// All-time inference water + your amortised training share.
    var lifetimeTotalML: Double {
        waterML(for: .all) + lifetimeTrainingShareML
    }

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
