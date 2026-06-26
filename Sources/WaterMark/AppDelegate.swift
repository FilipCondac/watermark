import AppKit
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let scanner = UsageScanner()
    private let water = WaterModel()
    private let scanQueue = DispatchQueue(label: "com.filipcondac.watermark.scan")
    private var timer: Timer?
    private var latest = UsageAggregate()

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

    private func windowTotals() -> (today: TokenTotals, last7: TokenTotals, all: TokenTotals) {
        let cal = Calendar.current
        let now = Date()
        let todayKey = UsageScanner.dayFmt.string(from: now)

        let today = latest.byDay[todayKey] ?? TokenTotals()

        var last7 = TokenTotals()
        for i in 0..<7 {
            if let d = cal.date(byAdding: .day, value: -i, to: now) {
                if let t = latest.byDay[UsageScanner.dayFmt.string(from: d)] { last7.add(t) }
            }
        }

        var all = TokenTotals()
        for (_, v) in latest.byDay { all.add(v) }

        return (today, last7, all)
    }

    // MARK: - UI

    private func updateUI() {
        let w = windowTotals()
        let todayWater = water.water(forTokens: w.today.effective)
        statusItem.button?.title = " " + Self.fmtWater(todayWater)

        let menu = NSMenu()

        menu.addItem(infoRow("Today", w.today))
        menu.addItem(infoRow("Last 7 days", w.last7))
        menu.addItem(infoRow("All time", w.all))

        menu.addItem(.separator())

        let byModel = NSMenuItem(title: "By model", action: nil, keyEquivalent: "")
        let modelMenu = NSMenu()
        let models = latest.byModel.sorted { $0.value.effective > $1.value.effective }
        if models.isEmpty {
            modelMenu.addItem(disabled("No usage found yet"))
        } else {
            for (model, t) in models {
                modelMenu.addItem(infoRow(model, t))
            }
        }
        byModel.submenu = modelMenu
        menu.addItem(byModel)

        menu.addItem(.separator())

        let rateItem = NSMenuItem(
            title: String(format: "Water rate: %.2f mL / 1k tokens", water.mlPer1kTokens),
            action: nil, keyEquivalent: ""
        )
        let rateMenu = NSMenu()
        for preset in [0.25, 0.5, 1.0, 2.0] {
            let item = NSMenuItem(
                title: String(format: "%.2f mL / 1k", preset),
                action: #selector(setPreset(_:)), keyEquivalent: ""
            )
            item.target = self
            item.representedObject = preset
            if abs(preset - water.mlPer1kTokens) < 0.0001 { item.state = .on }
            rateMenu.addItem(item)
        }
        rateMenu.addItem(.separator())
        rateMenu.addItem(menuItem("Custom…", #selector(setCustomRate)))
        rateItem.submenu = rateMenu
        menu.addItem(rateItem)

        menu.addItem(menuItem("Refresh now", #selector(refreshNow)))

        let login = menuItem("Launch at login", #selector(toggleLogin))
        login.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
        menu.addItem(login)

        menu.addItem(menuItem("About / methodology…", #selector(showAbout)))

        menu.addItem(.separator())
        menu.addItem(menuItem("Quit WaterMark", #selector(quit)))

        statusItem.menu = menu
    }

    private func infoRow(_ label: String, _ t: TokenTotals) -> NSMenuItem {
        let ml = water.water(forTokens: t.effective)
        let tokens = Self.tokenFmt.string(from: NSNumber(value: t.effective)) ?? "\(t.effective)"
        return disabled("\(label): \(Self.fmtWater(ml))  ·  \(tokens) tokens")
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

    private static func fmtWater(_ ml: Double) -> String {
        if ml >= 1000 { return String(format: "%.2f L", ml / 1000) }
        if ml >= 10 { return String(format: "%.0f mL", ml) }
        return String(format: "%.1f mL", ml)
    }

    // MARK: - Actions

    @objc private func setPreset(_ sender: NSMenuItem) {
        if let v = sender.representedObject as? Double {
            water.mlPer1kTokens = v
            updateUI()
        }
    }

    @objc private func setCustomRate() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Water rate"
        alert.informativeText = "How many millilitres of water per 1,000 tokens?"
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        field.stringValue = String(format: "%.3f", water.mlPer1kTokens)
        alert.accessoryView = field

        if alert.runModal() == .alertFirstButtonReturn {
            let normalized = field.stringValue.replacingOccurrences(of: ",", with: ".")
            if let v = Double(normalized), v > 0 {
                water.mlPer1kTokens = v
                updateUI()
            }
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

        Water = tokens ÷ 1000 × your configured rate. The default rate \
        (0.5 mL / 1k tokens) is a conservative midpoint — real data-centre \
        water use varies enormously with cooling design and local grid. \
        Treat the number as a rough indicator, not a measurement.

        Everything stays on your machine. Nothing is uploaded.
        """
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
