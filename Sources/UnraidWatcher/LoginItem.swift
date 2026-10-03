// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Ray Munro

import AppKit
import ServiceManagement
import SwiftUI

/// Launch at login, backed by the system's login item service. macOS is the source of truth:
/// the user can also change this in System Settings, General, Login Items.
@MainActor
final class LoginItem: ObservableObject {
    @Published private(set) var status = SMAppService.mainApp.status
    @Published var errorText: String?

    var isEnabled: Bool { status == .enabled }
    var needsApproval: Bool { status == .requiresApproval }
    /// Login items are most reliable when the app lives in an Applications folder.
    var inApplications: Bool {
        let p = Bundle.main.bundlePath
        return p.hasPrefix("/Applications/") || p.hasPrefix(NSHomeDirectory() + "/Applications/")
    }

    func refresh() { status = SMAppService.mainApp.status }

    func set(_ on: Bool) {
        errorText = nil
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            errorText = error.localizedDescription
        }
        refresh()
    }

    func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }
}

/// Starts the app quietly (menu bar only) when macOS launched it as a login item.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let hide = UserDefaults.standard.object(forKey: "hideWindowOnLoginLaunch") as? Bool ?? true
        guard hide, Self.launchedAsLoginItem else { return }
        // The window is created just after launch, so close it once it exists. The menu bar item keeps running.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            NSApp.windows.filter { $0.title == "Unraid Watcher" }.forEach { $0.close() }
        }
    }

    /// True when the open-application Apple event says the system launched us as a login item.
    static var launchedAsLoginItem: Bool {
        let keyAEPropData: AEKeyword = 0x70726474            // 'prdt'
        let keyAELaunchedAsLogInItem: UInt32 = 0x6c676974    // 'lgit'
        guard let event = NSAppleEventManager.shared().currentAppleEvent else { return false }
        return event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }
}
