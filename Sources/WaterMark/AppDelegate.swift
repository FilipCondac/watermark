import AppKit
import ServiceManagement

/// Which usage window the menu-bar figure reflects.
enum BarWindow: String, CaseIterable {
    case today, week, month, all

    var title: String {
        switch self {
        case .today: return "Today"
        case .week:  return "Last 7 days"
        case .month: return "Last 30 days"
        case .all:   return "All time"
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let scanner = UsageScanner()
    private let water = WaterModel()
    private let scanQueue = DispatchQueue(label: "com.filipcondac.watermark.scan")
    private var timer: Timer?
    private var latest = UsageAggregate()

    /// Per-model rate presets offered in the menu (mL / 1k tokens).
    private let ratePresets: [Double] = [0.1, 0.25, 0.5, 1.0, 2.0]

    /// Window shown in the menu bar (persisted).
    private var barWindow: BarWindow {
        get { BarWindow(rawValue: UserDefaults.standard.string(forKey: "barWindow") ?? "") ?? .today }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "barWindow") }
    }

    /// Carried on a menu item so an action knows which model + rate to apply.
    private struct RateChange { let model: String; let rate: Double }

    private static let tokenFmt: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            let drop = NSImage(systemSymbolName: "drop.fill", accessibilityDescription: "WaterMark")
            drop?.isTemplate = true  // tints to match the menu bar (light/dark)
            button.image = drop
            button.imagePosition = .imageLeading
            button.title = " …"
            button.toolTip = "WaterMark — estimated water from Claude Code usage"
        }

        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    // MARK: - Data

    private func refresh() {
        scanQueue.async { [scanner] in
            let agg = scanner.scan()
            DispatchQueue.main.async { [weak self] in
                self?.latest = agg
                self?.updateUI()
            }
        }
    }

    /// Per-model token totals over a set of day keys (nil = all time).
    private func tokens(forDays days: [String]?) -> [String: TokenTotals] {
        var out: [String: TokenTotals] = [:]
        let filter = days.map(Set.init)
        for (day, models) in latest.byDayModel {
            if let filter, !filter.contains(day) { continue }
            for (model, t) in models { out[model, default: TokenTotals()].add(t) }
        }
        return out
    }

    private func lastNDayKeys(_ n: Int) -> [String] {
        let cal = Calendar.current
        let now = Date()
        return (0..<n).compactMap { cal.date(byAdding: .day, value: -$0, to: now) }
            .map { UsageScanner.dayFmt.string(from: $0) }
    }

    private func todayKey() -> String { UsageScanner.dayFmt.string(from: Date()) }

    /// Total water across all models, each at its own rate.
    private func water(_ perModel: [String: TokenTotals]) -> Double {
        perModel.reduce(0.0) { $0 + water.water(forModel: $1.key, tokens: $1.value.effective) }
    }

    private func tokenSum(_ perModel: [String: TokenTotals]) -> Int {
        perModel.values.reduce(0) { $0 + $1.effective }
    }

    // MARK: - UI

    private func updateUI() {
        let perWindow: [BarWindow: [String: TokenTotals]] = [
            .today: tokens(forDays: [todayKey()]),
            .week:  tokens(forDays: lastNDayKeys(7)),
            .month: tokens(forDays: lastNDayKeys(30)),
            .all:   tokens(forDays: nil),
        ]
        let all = perWindow[.all] ?? [:]
        let selected = perWindow[barWindow] ?? [:]

        if let button = statusItem.button {
            button.title = " " + Self.fmtWater(water(selected))
            button.toolTip = "WaterMark — \(barWindow.title.lowercased()) water from Claude Code usage"
        }

        let menu = NSMenu()

        for w in BarWindow.allCases {
            menu.addItem(infoRow(w.title, perWindow[w] ?? [:], checked: w == barWindow))
        }

        menu.addItem(.separator())

        // Per-model breakdown (all time), each at its own rate.
        let byModel = NSMenuItem(title: "By model", action: nil, keyEquivalent: "")
        let modelMenu = NSMenu()
        let sorted = all.sorted { $0.value.effective > $1.value.effective }
        if sorted.isEmpty {
            modelMenu.addItem(disabled("No usage found yet"))
        } else {
            for (model, t) in sorted {
                let ml = water.water(forModel: model, tokens: t.effective)
                modelMenu.addItem(disabled("\(model): \(Self.fmtWater(ml))  ·  \(Self.fmtTokens(t.effective)) tok"))
            }
        }
        byModel.submenu = modelMenu
        menu.addItem(byModel)

        // Per-model editable rates.
        let ratesParent = NSMenuItem(title: "Water rates (mL / 1k tokens)", action: nil, keyEquivalent: "")
        ratesParent.submenu = buildRatesMenu(models: all.keys.sorted())
        menu.addItem(ratesParent)

        // Which window the menu-bar figure shows.
        let barParent = NSMenuItem(title: "Show in menu bar", action: nil, keyEquivalent: "")
        let barMenu = NSMenu()
        for w in BarWindow.allCases {
            let item = NSMenuItem(title: w.title, action: #selector(setBarWindow(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = w.rawValue
            if w == barWindow { item.state = .on }
            barMenu.addItem(item)
        }
        barParent.submenu = barMenu
        menu.addItem(barParent)

        menu.addItem(.separator())

        menu.addItem(menuItem("Refresh now", #selector(refreshNow)))

        let login = menuItem("Launch at login", #selector(toggleLogin))
        login.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
        menu.addItem(login)

        menu.addItem(menuItem("About / methodology…", #selector(showAbout)))

        menu.addItem(.separator())
        menu.addItem(menuItem("Quit WaterMark", #selector(quit)))

        statusItem.menu = menu
    }

    private func buildRatesMenu(models: [String]) -> NSMenu {
        let menu = NSMenu()
        if models.isEmpty {
            menu.addItem(disabled("No usage yet"))
            return menu
        }
        for model in models {
            let rate = water.rate(for: model)
            let parent = NSMenuItem(
                title: String(format: "%@  ·  %.2f", model, rate),
                action: nil, keyEquivalent: ""
            )
            let sub = NSMenu()
            for preset in ratePresets {
                let item = NSMenuItem(
                    title: String(format: "%.2f mL / 1k", preset),
                    action: #selector(setModelPreset(_:)), keyEquivalent: ""
                )
                item.target = self
                item.representedObject = RateChange(model: model, rate: preset)
                if abs(preset - rate) < 0.0001 { item.state = .on }
                sub.addItem(item)
            }
            sub.addItem(.separator())

            let custom = NSMenuItem(title: "Custom…", action: #selector(setModelCustom(_:)), keyEquivalent: "")
            custom.target = self
            custom.representedObject = model
            sub.addItem(custom)

            let def = water.defaultRate(for: model)
            let reset = NSMenuItem(
                title: String(format: "Reset to default (%.2f)", def),
                action: #selector(resetModelRate(_:)), keyEquivalent: ""
            )
            reset.target = self
            reset.representedObject = model
            sub.addItem(reset)

            parent.submenu = sub
            menu.addItem(parent)
        }
        return menu
    }

    private func infoRow(_ label: String, _ perModel: [String: TokenTotals], checked: Bool = false) -> NSMenuItem {
        let ml = water(perModel)
        let tokens = Self.fmtTokens(tokenSum(perModel))
        let item = disabled("\(label): \(Self.fmtWater(ml))  ·  \(tokens) tokens")
        if checked { item.state = .on }  // marks the window currently in the menu bar
        return item
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func menuItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private static func fmtTokens(_ n: Int) -> String {
        tokenFmt.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    private static func fmtWater(_ ml: Double) -> String {
        if ml >= 1000 { return String(format: "%.2f L", ml / 1000) }
        if ml >= 10 { return String(format: "%.0f mL", ml) }
        return String(format: "%.1f mL", ml)
    }

    // MARK: - Actions

    @objc private func setModelPreset(_ sender: NSMenuItem) {
        if let c = sender.representedObject as? RateChange {
            water.setRate(c.rate, for: c.model)
            updateUI()
        }
    }

    @objc private func setModelCustom(_ sender: NSMenuItem) {
        guard let model = sender.representedObject as? String else { return }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Water rate — \(model)"
        alert.informativeText = "Millilitres of water per 1,000 tokens for this model."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        field.stringValue = String(format: "%.3f", water.rate(for: model))
        alert.accessoryView = field

        if alert.runModal() == .alertFirstButtonReturn {
            let normalized = field.stringValue.replacingOccurrences(of: ",", with: ".")
            if let v = Double(normalized), v > 0 {
                water.setRate(v, for: model)
                updateUI()
            }
        }
    }

    @objc private func resetModelRate(_ sender: NSMenuItem) {
        if let model = sender.representedObject as? String {
            water.resetRate(for: model)
            updateUI()
        }
    }

    @objc private func setBarWindow(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let w = BarWindow(rawValue: raw) {
            barWindow = w
            updateUI()
        }
    }

    @objc private func refreshNow() { refresh() }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSApp.activate(ignoringOtherApps: true)
            let a = NSAlert(error: error)
            a.messageText = "Couldn't change launch-at-login"
            a.runModal()
        }
        updateUI()
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "WaterMark"
        alert.informativeText = """
        Estimates the water footprint of your Claude Code usage from local \
        transcripts in ~/.claude/projects.

        Tokens counted: input + output + cache-creation (cache *reads* are \
        excluded as cheap retrieval).

        Water = tokens ÷ 1000 × the rate for that model, summed across models. \
        Each model has its own editable rate under "Water rates"; the defaults \
        scale with model size (Opus 0.80, Sonnet 0.40, Haiku 0.15 mL / 1k). \
        Real data-centre water use varies enormously with cooling design and \
        local grid, so treat the number as a rough indicator, not a measurement.

        Everything stays on your machine. Nothing is uploaded.
        """
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
