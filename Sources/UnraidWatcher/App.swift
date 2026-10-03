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
        .applicationVersion: "1.1.0",
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
    @StateObject private var store = Store()
    init() { migrateOldDefaults() }

    var body: some Scene {
        Window("Unraid Watcher", id: "main") {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 860, minHeight: 560)
                .task { store.start() }
        }
        .commands {
            CommandGroup(replacing: .appInfo) { Button("About Unraid Watcher") { showAboutPanel() } }
        }
        Settings { SettingsView().environmentObject(store) }
        MenuBarExtra {
            MenuBarView().environmentObject(store)
        } label: {
            Image(systemName: store.connected ? "externaldrive.connected.to.line.below" : "externaldrive.badge.xmark")
        }
        .menuBarExtraStyle(.window)
    }
}
