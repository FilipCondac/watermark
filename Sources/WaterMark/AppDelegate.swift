import AppKit
import SwiftUI
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private let scanner = UsageScanner()
    private let state = AppState()
    private let scanQueue = DispatchQueue(label: "com.filipcondac.watermark.scan")
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            let drop = NSImage(systemSymbolName: "drop.fill", accessibilityDescription: "WaterMark")
            drop?.isTemplate = true  // tints to match the menu bar (light/dark)
            button.image = drop
            button.imagePosition = .imageLeading
            button.title = " …"
            button.action = #selector(togglePopover(_:))
            button.target = self
        }

        popover.behavior = .transient
        popover.animates = true
        let host = NSHostingController(rootView: DashboardView(state: state))
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host

        state.refreshHandler = { [weak self] in self?.refresh() }

        // Keep the menu-bar figure in sync with state changes (window switch, new scan).
        state.objectWillChange
            .sink { [weak self] in
                DispatchQueue.main.async { self?.updateBarTitle() }
            }
            .store(in: &cancellables)

        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    private func refresh() {
        scanQueue.async { [scanner] in
            let agg = scanner.scan()
            DispatchQueue.main.async { [weak self] in
                self?.state.aggregate = agg
                self?.updateBarTitle()
            }
        }
    }

    private func updateBarTitle() {
        let ml = state.waterML(for: state.barWindow)
        statusItem.button?.title = " " + AppState.fmtWater(ml)
        statusItem.button?.toolTip = "WaterMark — \(state.barWindow.title) water from Claude Code"
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
