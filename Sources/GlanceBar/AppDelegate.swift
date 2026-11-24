import AppKit
import GlanceCore
import ServiceManagement
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, NSViewToolTipOwner {
    let monitor: Monitor
    private var statusItem: NSStatusItem!
    private let barView = BarView()
    private var popover: NSPopover?
    private var panel: PanelModel?
    /// The width last given to the status item. Resizing it makes AppKit and the window server
    /// rebuild the item on every display, so it happens only when the content's width changes.
    private var itemWidth: CGFloat = 0

    init(demo: Bool) {
        monitor = Monitor(demo: demo)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let id = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: id).count > 1 {
            NSApp.terminate(nil)  // one menu bar item is enough
            return
        }
        installMainMenu()
        statusItem = NSStatusBar.system.statusItem(withLength: 24)
        // Demo mode leaves no trace: no login item and no remembered position.
        if !monitor.demo {
            LoginItem.enableOnFirstInstalledLaunch()
            statusItem.autosaveName = "GlanceBar"
        }
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.setAccessibilityLabel("Glance Bar system stats")
            barView.frame = button.bounds
            barView.autoresizingMask = [.width, .height]
            button.addSubview(barView)
        }

        monitor.onChange = { [weak self] in self?.update() }
        monitor.start()
        update()
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor.stop()
    }

    /// One pass per tick: the bar redraws only if its pixels would change, and the panel is fed
    /// only while it is open.
    private func update() {
        let content = BarContent.make(snapshot: monitor.snapshot,
                                      cpuHistory: monitor.cpuHistory.suffix(BarContent.graphBars),
                                      visible: monitor.settings.visible,
                                      temperatureUnit: monitor.settings.temperatureUnit)
        let width = BarRenderer.width(of: content)
        if width != itemWidth {
            itemWidth = width
            statusItem.length = width
            coverWithToolTip(width: width)
        }
        barView.content = content
        panel?.refresh()
    }

    /// The tooltip covers the item at its current width. Its text is asked for only when the
    /// pointer rests on the item, so it costs nothing per tick.
    private func coverWithToolTip(width: CGFloat) {
        guard let button = statusItem.button else { return }
        button.removeAllToolTips()
        let height = max(button.bounds.height, NSStatusBar.system.thickness, 44)
        button.addToolTip(NSRect(x: 0, y: 0, width: width, height: height), owner: self, userData: nil)
    }

    func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint,
              userData data: UnsafeMutableRawPointer?) -> String {
        // A meter shows in the item only when it has a reading, so the lines match what is drawn.
        let lines = BarSummary.lines(snapshot: monitor.snapshot, visible: monitor.settings.visible,
                                     temperatureUnit: monitor.settings.temperatureUnit)
        return (lines + ["Click for details, right-click for the menu"]).joined(separator: "\n")
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            popover?.performClose(sender)
            showQuickMenu()
        } else if let popover, popover.isShown {
            popover.performClose(sender)
        } else {
            showPanel(from: sender)
        }
    }

    /// The panel is built when it opens and dropped when it closes: between
    /// clicks the app holds no SwiftUI views at all.
    private func showPanel(from button: NSStatusBarButton, settings: Bool = false) {
        monitor.setPanelOpen(true)
        let panel = PanelModel(monitor: monitor)
        panel.showingSettings = settings
        let host = NSHostingController(rootView: PanelView().environment(panel))
        host.sizingOptions = [.preferredContentSize]
        let popover = NSPopover()
        popover.contentViewController = host
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        self.panel = panel
        self.popover = popover
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        host.view.window?.makeKey()
    }

    func popoverDidClose(_ notification: Notification) {
        monitor.setPanelOpen(false)
        panel = nil
        popover = nil
    }

    private func showQuickMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Open Activity Monitor", action: #selector(openActivityMonitor), keyEquivalent: "")
            .target = self
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Glance Bar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func installMainMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Settings…", action: #selector(toggleSettings), keyEquivalent: ",").target = self
        appMenu.addItem(withTitle: "Close", action: #selector(closePanel), keyEquivalent: "w").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Glance Bar", action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")
        appItem.submenu = appMenu
        menu.addItem(appItem)
        NSApp.mainMenu = menu
    }

    @objc private func openActivityMonitor() { Actions.openActivityMonitor() }

    @objc private func openSettings() {
        if let panel, popover?.isShown == true {
            panel.showingSettings = true
        } else if let button = statusItem.button {
            showPanel(from: button, settings: true)
        }
    }

    @objc private func toggleSettings() {
        if let panel, popover?.isShown == true {
            panel.showingSettings.toggle()
        } else if let button = statusItem.button {
            showPanel(from: button, settings: true)
        }
    }

    @objc private func closePanel() {
        popover?.performClose(nil)
    }
}

/// A System Settings pane, by the identifier its settings extension registers.
enum SettingsPane: String {
    case about = "com.apple.SystemProfiler.AboutExtension"
    case battery = "com.apple.Battery-Settings.extension"
    case network = "com.apple.Network-Settings.extension"
    case storage = "com.apple.settings.Storage"

    var url: URL? { URL(string: "x-apple.systempreferences:\(rawValue)") }
}

enum Actions {
    static func openActivityMonitor() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.ActivityMonitor")
        else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    /// A pane macOS no longer has leaves System Settings on its first page.
    static func open(_ pane: SettingsPane) {
        if let url = pane.url { NSWorkspace.shared.open(url) }
    }

    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
    static var requiresApproval: Bool { SMAppService.mainApp.status == .requiresApproval }

    /// Turns "Open at Login" on once, the first time an installed copy runs. The settings toggle
    /// can turn it off for good. A registration that fails is tried again at the next launch.
    static func enableOnFirstInstalledLaunch() {
        let key = "loginItemInitialized"
        let path = Bundle.main.bundleURL.path
        guard path.hasSuffix(".app"), path.contains("/Applications/"),
              !UserDefaults.standard.bool(forKey: key) else { return }
        if isEnabled || set(true) == nil { UserDefaults.standard.set(true, forKey: key) }
    }

    static func set(_ enabled: Bool) -> String? {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
