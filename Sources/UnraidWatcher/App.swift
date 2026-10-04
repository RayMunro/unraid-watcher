// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Ray Munro

import SwiftUI
import AppKit

let copyrightLine = "© 2026 Ray Munro"

/// Carry settings over from the app's earlier bundle id (before it was renamed Unraid Watcher).
func migrateOldDefaults() {
    let d = UserDefaults.standard
    guard d.object(forKey: "migratedFromUnraidMonitor") == nil else { return }
    for suite in ["com.raymondmunro.towerlight", "com.local.unraidmonitor"] {
        guard let old = UserDefaults(suiteName: suite) else { continue }
        for k in ["serverURL", "allowInsecure", "refreshSeconds", "sshEnabled", "sshUser", "notifyEnabled", "diskWarnTemp", "diskCritTemp", "cpuWarnTemp"] {
            if d.object(forKey: k) == nil, let v = old.object(forKey: k) { d.set(v, forKey: k) }
        }
    }
    d.set(true, forKey: "migratedFromUnraidMonitor")
}

func showAboutPanel() {
    NSApp.orderFrontStandardAboutPanel(options: [
        .applicationName: "Unraid Watcher",
        .applicationVersion: "1.4.0",
        .version: "",
        .credits: NSAttributedString(string: "A native Mac dashboard and control panel for your Unraid server.\n\n\(copyrightLine). Licensed under the GNU GPL v3 or later.",
                                     attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]),
        NSApplication.AboutPanelOptionKey(rawValue: "Copyright"): "\(copyrightLine). Licensed under the GNU GPL v3 or later.",
    ])
    NSApp.activate(ignoringOtherApps: true)
}

@main
struct UnraidWatcherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var manager = ServerManager()
    init() { migrateOldDefaults() }

    var body: some Scene {
        Window("Unraid Watcher", id: "main") {
            RootView()
                .environmentObject(manager)
                .frame(minWidth: 860, minHeight: 560)
        }
        .commands {
            CommandGroup(replacing: .appInfo) { Button("About Unraid Watcher") { showAboutPanel() } }
            CommandMenu("Servers") {
                ForEach(Array(manager.servers.prefix(9).enumerated()), id: \.element.id) { i, p in
                    Button(p.name) { manager.select(p.id) }.keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command)
                }
                if manager.servers.count > 1 {
                    Divider()
                    Button("All Servers") { manager.select(nil) }.keyboardShortcut("0", modifiers: .command)
                }
            }
        }
        Settings { SettingsView().environmentObject(manager) }
        MenuBarExtra {
            MenuBarView().environmentObject(manager)
        } label: {
            HStack(spacing: 3) {
                Image(systemName: manager.allConnected ? "externaldrive.connected.to.line.below" : "externaldrive.badge.xmark")
                if let p = manager.operationPercent { Text(p).monospacedDigit() }
            }
        }
        .menuBarExtraStyle(.window)
    }
}
