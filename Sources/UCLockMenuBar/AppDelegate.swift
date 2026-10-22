import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let model = LockModel()
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let doorbellPanel = DoorbellPanelController()
    private var cancellables = Set<AnyCancellable>()
    private var flashReset: DispatchWorkItem?
    private var globalClickMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installStatusItem()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )

        popover = NSPopover()
        popover.delegate = self
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: PopoverView(model: model))

        model.onDoorbell = { [weak self] activity in
            guard let self else { return }
            self.doorbellPanel.show(
                activity: activity,
                onOpen: { [weak self] in self?.showPopover() },
                onDismiss: {}
            )
        }

        model.onDoorbellPhoto = { [weak self] activity, url in
            self?.doorbellPanel.updatePhoto(url, for: activity)
        }

        model.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.updateStatusItem() }
            }
            .store(in: &cancellables)

        NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.closePopoverIfShown() }
        }

        updateStatusItem()
        model.start()
        Task { await model.refresh() }
    }

    private func installStatusItem() {
        if statusItem != nil {
            NSStatusBar.system.removeStatusItem(statusItem)
            statusItem = nil
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = "UCLockStatusItem"
        if let button = statusItem.button {
            button.image = menuIcon() ?? NSImage(systemSymbolName: "lock.shield.fill", accessibilityDescription: "UC Lock")
            button.imagePosition = .imageOnly
            button.action = #selector(togglePopover)
            button.target = self
            button.toolTip = "UC Lock"
        }
        updateStatusItem()
    }

    @objc private func screensChanged() {
        // A display change can leave the status item attached to a menu bar that
        // no longer exists, which hides the icon. Rebuild it on the current bar.
        DispatchQueue.main.async { [weak self] in self?.installStatusItem() }
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        doorbellPanel.close()
        if !popover.isShown {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
        NSApp.activate(ignoringOtherApps: true)
        popover.contentViewController?.view.window?.makeKey()
        installGlobalClickMonitor()
        Task { await model.refresh() }
    }

    private func closePopoverIfShown() {
        if popover.isShown {
            popover.performClose(nil)
        }
    }

    private func installGlobalClickMonitor() {
        guard globalClickMonitor == nil else { return }
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in self?.closePopoverIfShown() }
        }
    }

    func popoverDidClose(_ notification: Notification) {
        if let monitor = globalClickMonitor {
            NSEvent.removeMonitor(monitor)
            globalClickMonitor = nil
        }
    }

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }
        let ringing = model.pendingDoorbell != nil
        if ringing {
            button.image = NSImage(systemSymbolName: "bell.badge.fill", accessibilityDescription: "Doorbell")
        } else {
            button.image = menuIcon() ?? NSImage(systemSymbolName: "lock.shield.fill", accessibilityDescription: "UC Lock")
        }
        button.title = ""
        var tip = "UC Lock"
        if let battery = model.device.battery {
            tip += " · battery \(battery)%"
        }
        if let doorbell = model.pendingDoorbell {
            tip += " · doorbell \(doorbell.timeText)"
        }
        button.toolTip = tip
    }

    private func menuIcon() -> NSImage? {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("MenuIcon.png"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }

    private func flashBell() {
        flashReset?.cancel()
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "bell.badge.fill", accessibilityDescription: "Doorbell")
        }
        let reset = DispatchWorkItem { [weak self] in self?.updateStatusItem() }
        flashReset = reset
        DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: reset)
    }
}
