// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Ray Munro

import AppKit
import Combine
import SwiftUI

// MARK: - Profile

struct ServerProfile: Codable, Identifiable, Equatable, Hashable {
    var id = UUID()
    var name = "My Unraid"
    var url = ""
    var allowInsecure = true
    var sshEnabled = false
    var sshUser = "root"
    /// Optional address of the Deluge Web UI. Empty means find it on the server automatically.
    var delugeURL = ""

    init() {}

    // Servers saved by older versions lack newer keys, so every key is optional when decoding.
    private enum Keys: String, CodingKey { case id, name, url, allowInsecure, sshEnabled, sshUser, delugeURL }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "My Unraid"
        url = try c.decodeIfPresent(String.self, forKey: .url) ?? ""
        allowInsecure = try c.decodeIfPresent(Bool.self, forKey: .allowInsecure) ?? true
        sshEnabled = try c.decodeIfPresent(Bool.self, forKey: .sshEnabled) ?? false
        sshUser = try c.decodeIfPresent(String.self, forKey: .sshUser) ?? "root"
        delugeURL = try c.decodeIfPresent(String.self, forKey: .delugeURL) ?? ""
    }

    var host: String? {
        var s = url.trimmingCharacters(in: .whitespaces)
        if !s.isEmpty && !s.contains("://") { s = "http://" + s }
        return URL(string: s)?.host
    }
}

// MARK: - Manager

/// Owns every configured server. Each server gets its own `Store` that polls in the background,
/// so alerts keep working for all of them, whichever one is on screen.
@MainActor
final class ServerManager: ObservableObject {
    @Published private(set) var servers: [ServerProfile] = []
    @Published private(set) var selectedID: UUID?
    private(set) var stores: [UUID: Store] = [:]
    private var watchers: [UUID: AnyCancellable] = [:]

    private static let serversKey = "servers"
    private static let selectedKey = "selectedServer"   // a UUID string, or "" for the all-servers overview

    init() {
        let d = UserDefaults.standard
        if let data = d.data(forKey: Self.serversKey), let list = try? JSONDecoder().decode([ServerProfile].self, from: data) { servers = list }
        migrateSingleServerSettings()
        for p in servers { makeStore(for: p) }
        if let raw = d.string(forKey: Self.selectedKey) {
            selectedID = UUID(uuidString: raw).flatMap { id in servers.contains { $0.id == id } ? id : nil }
        } else {
            selectedID = servers.first?.id
        }
        refreshNames()
    }

    var selectedStore: Store? { selectedID.flatMap { stores[$0] } }
    /// "37%" for the menu bar while a server is rebuilding or checking its array, nil otherwise. With several, the one furthest behind.
    var operationPercent: String? {
        let ops = servers.compactMap { stores[$0.id]?.arrayOp }
        guard let slowest = ops.min(by: { $0.progress < $1.progress }) else { return nil }
        return "\(Int(slowest.progress * 100))%"
    }
    var allConnected: Bool { !servers.isEmpty && servers.allSatisfy { stores[$0.id]?.connected == true } }

    func select(_ id: UUID?) {
        selectedID = id
        UserDefaults.standard.set(id?.uuidString ?? "", forKey: Self.selectedKey)
    }

    /// Adds a new server, or replaces an existing one, with its secrets. The server then reconnects.
    func save(_ profile: ServerProfile, apiKey: String, sshPassword: String, delugePassword: String = "") {
        if let i = servers.firstIndex(where: { $0.id == profile.id }) { servers[i] = profile } else { servers.append(profile) }
        Keychain.set("apiKey.\(profile.id)", apiKey)
        Keychain.set("sshPassword.\(profile.id)", sshPassword)
        Keychain.set("delugePassword.\(profile.id)", delugePassword)
        stores[profile.id]?.stop()
        makeStore(for: profile, apiKey: apiKey, sshPassword: sshPassword, delugePassword: delugePassword)
        persist()
        refreshNames()
        if selectedID == nil && servers.count == 1 { select(profile.id) }
        objectWillChange.send()
    }

    @discardableResult
    func addBlank() -> ServerProfile {
        var p = ServerProfile()
        p.name = "Server \(servers.count + 1)"
        save(p, apiKey: "", sshPassword: "")
        return p
    }

    func remove(_ id: UUID) {
        stores[id]?.stop()
        stores[id] = nil; watchers[id] = nil
        Keychain.set("apiKey.\(id)", ""); Keychain.set("sshPassword.\(id)", ""); Keychain.set("delugePassword.\(id)", "")
        servers.removeAll { $0.id == id }
        persist()
        refreshNames()
        if selectedID == id { select(servers.first?.id) }
    }

    // MARK: private

    private func persist() {
        if let data = try? JSONEncoder().encode(servers) { UserDefaults.standard.set(data, forKey: Self.serversKey) }
    }

    private func makeStore(for p: ServerProfile, apiKey: String? = nil, sshPassword: String? = nil, delugePassword: String? = nil) {
        let s = Store(profile: p, apiKey: apiKey ?? Keychain.get("apiKey.\(p.id)"), sshPassword: sshPassword ?? Keychain.get("sshPassword.\(p.id)"),
                      delugePassword: delugePassword ?? Keychain.get("delugePassword.\(p.id)"))
        stores[p.id] = s
        // re-render the menu bar icon and server picker when a server goes up or down
        // also follow array operations, so the menu bar percentage keeps up as it changes
        watchers[p.id] = Publishers.Merge(s.$connected.removeDuplicates().map { _ in () }, s.$arrayOp.map { _ in () }).sink { [weak self] _ in self?.objectWillChange.send() }
        s.showServerName = servers.count > 1
        s.start()
    }

    private func refreshNames() { for s in stores.values { s.showServerName = servers.count > 1 } }

    /// Versions before multi-server kept one server in plain settings. Turn it into the first server.
    private func migrateSingleServerSettings() {
        let d = UserDefaults.standard
        guard servers.isEmpty, d.object(forKey: "migratedToServerList") == nil else { return }
        d.set(true, forKey: "migratedToServerList")
        guard let url = d.string(forKey: "serverURL"), !url.isEmpty else { return }
        var p = ServerProfile()
        p.url = url
        p.name = p.host ?? "My Unraid"
        p.allowInsecure = d.object(forKey: "allowInsecure") as? Bool ?? true
        p.sshEnabled = d.bool(forKey: "sshEnabled")
        p.sshUser = d.string(forKey: "sshUser") ?? "root"
        for (old, new) in [("apiKey", "apiKey.\(p.id)"), ("sshPassword", "sshPassword.\(p.id)")] {
            let value = Keychain.get(old)
            guard !value.isEmpty else { continue }
            Keychain.set(new, value)
            if Keychain.get(new) == value { Keychain.set(old, "") }     // remove the old item only once the copy is confirmed
        }
        servers = [p]
        persist()
        d.set(p.id.uuidString, forKey: Self.selectedKey)
    }
}

// MARK: - Root and picker

struct RootView: View {
    @EnvironmentObject var manager: ServerManager
    var body: some View {
        if let store = manager.selectedStore {
            ServerContentView().environmentObject(store)
        } else {
            AllServersView()
        }
    }
}

struct ServerPicker: View {
    @EnvironmentObject var manager: ServerManager
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        let current = manager.selectedID.flatMap { id in manager.servers.first { $0.id == id } }
        let store = manager.selectedStore
        Menu {
            ForEach(manager.servers) { p in
                Button { manager.select(p.id) } label: {
                    if p.id == manager.selectedID { Label(p.name, systemImage: "checkmark") } else { Text(p.name) }
                }
            }
            if manager.servers.count > 1 {
                Divider()
                Button("All servers") { manager.select(nil) }
            }
            Divider()
            Button("Manage servers…") { openSettings() }
        } label: {
            HStack(spacing: 7) {
                Circle().fill(current == nil ? Color.blue : store?.connected == true ? .green : store?.configured == true ? .red : .gray).frame(width: 9, height: 9)
                Text(current?.name ?? "All servers").font(.callout.weight(.semibold)).lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden)
        .help("Switch server")
    }
}

// MARK: - All servers overview

struct AllServersView: View {
    @EnvironmentObject var manager: ServerManager
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    ServerPicker().frame(width: 240)
                    Spacer()
                    Button("Refresh all") { for s in manager.stores.values { Task { await s.refresh() } } }
                        .disabled(manager.servers.isEmpty)
                }
                if manager.servers.isEmpty {
                    ContentUnavailableView {
                        Label("No servers yet", systemImage: "server.rack")
                    } description: {
                        Text("Add your Unraid server's address and API key to get started.")
                    } actions: {
                        Button("Add a server") { openSettings() }
                    }.frame(maxWidth: .infinity, minHeight: 300)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 16, alignment: .top)], spacing: 16) {
                        ForEach(manager.servers) { p in
                            if let st = manager.stores[p.id] { ServerCard(store: st) }
                        }
                    }
                }
                Text("\(copyrightLine)").font(.caption).foregroundStyle(.tertiary).frame(maxWidth: .infinity, alignment: .center).padding(.top, 8)
            }.padding(20)
        }
        .frame(minWidth: 640)
    }
}

struct ServerCard: View {
    @ObservedObject var store: Store
    @EnvironmentObject var manager: ServerManager

    var body: some View {
        let hot = store.allDisks.compactMap(\.temp).max()
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(store.profile.name).font(.headline)
                Spacer()
                if !store.configured { Pill(text: "Not set up", color: .gray) }
                else if store.connected { Pill(text: "Connected", color: .green) }
                else { Pill(text: "Offline", color: .red) }
            }
            Text(store.profile.host ?? store.profile.url).font(.caption).foregroundStyle(.secondary)
            if store.connected {
                Divider()
                HStack { Text("Array").foregroundStyle(.secondary); Spacer(); Pill(text: store.array?.state ?? "-", color: stateColor(store.array?.state)) }
                if let kb = store.array?.capacity?.kilobytes, let t = kb.total?.value, t > 0 {
                    UsageBar(fraction: (kb.used?.value ?? 0) / t)
                    Text("\(bytes(kb.used?.value ?? 0)) used of \(bytes(t))").font(.caption).foregroundStyle(.secondary)
                }
                if let op = store.arrayOp {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack { Text(op.title).font(.caption.weight(.semibold)); Spacer(); Text(String(format: "%.0f%%", op.progress * 100)).font(.caption.monospacedDigit()) }
                        TorrentBar(fraction: op.progress, color: op.paused ? .orange : .blue, height: 6)
                        if let left = store.opSecondsLeft { Text("about \(durationText(left)) left").font(.caption2).foregroundStyle(.secondary) }
                    }
                }
                HStack(spacing: 14) {
                    stat("CPU", String(format: "%.0f%%", store.overview?.metrics?.cpu?.percentTotal ?? 0))
                    stat("RAM", String(format: "%.0f%%", store.overview?.metrics?.memory?.percentTotal ?? 0))
                    stat("Docker", "\(store.containers.filter(\.isRunning).count)/\(store.containers.count)")
                    stat("VMs", "\(store.vms.filter { $0.state?.uppercased() == "RUNNING" }.count)/\(store.vms.count)")
                }
                HStack(spacing: 12) {
                    if let hot { Label("\(Int(hot))°C", systemImage: "thermometer.medium").foregroundStyle(store.tempColor(hot)) }
                    if let n = store.notificationCounts?.total, n > 0 { Label("\(n) alerts", systemImage: "bell.fill").foregroundStyle(.orange) }
                    if !store.hotDisks.isEmpty { Label("\(store.hotDisks.count) hot", systemImage: "flame.fill").foregroundStyle(.red) }
                }.font(.caption)
            } else if store.configured, let e = store.errors.values.first {
                Text(e).font(.caption).foregroundStyle(.orange).lineLimit(3)
            }
            if let t = store.lastUpdated { Text("Updated \(t, style: .time)").font(.caption2).foregroundStyle(.tertiary) }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
        .onTapGesture { manager.select(store.profile.id) }
        .help("Open \(store.profile.name)")
    }

    func stat(_ k: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 1) { Text(v).font(.callout.weight(.semibold).monospacedDigit()); Text(k).font(.caption2).foregroundStyle(.secondary) }
    }
}

// MARK: - Menu bar

struct MenuBarView: View {
    @EnvironmentObject var manager: ServerManager
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if manager.servers.isEmpty { Text("No servers yet").foregroundStyle(.secondary) }
            ForEach(manager.servers) { p in
                if let st = manager.stores[p.id] {
                    Button { manager.select(p.id); openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) } label: {
                        MenuBarRow(store: st).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    if p.id != manager.servers.last?.id { Divider() }
                }
            }
            Divider()
            Button("Open Dashboard") { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
            SettingsLink { Text("Settings…") }
            Button("About Unraid Watcher") { showAboutPanel() }
            Button("Quit") { NSApplication.shared.terminate(nil) }
            Text(copyrightLine).font(.caption2).foregroundStyle(.secondary)
        }.padding(12).frame(width: 260)
    }
}

struct MenuBarRow: View {
    @ObservedObject var store: Store
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Circle().fill(store.connected ? Color.green : store.configured ? .red : .gray).frame(width: 8, height: 8)
                Text(store.profile.name).font(.headline)
            }
            if store.configured && store.connected {
                Text("Array: \(store.array?.state ?? "-")").font(.callout)
                if let op = store.arrayOp { Text("\(op.title): \(Int(op.progress * 100))%").font(.callout).foregroundStyle(.blue) }
                Text(String(format: "CPU %.0f%%  ·  RAM %.0f%%", store.overview?.metrics?.cpu?.percentTotal ?? 0, store.overview?.metrics?.memory?.percentTotal ?? 0)).font(.callout)
                Text("Docker: \(store.containers.filter(\.isRunning).count)/\(store.containers.count) running").font(.callout)
                if let n = store.notificationCounts?.total, n > 0 { Text("\(n) unread notifications").font(.callout).foregroundStyle(.orange) }
            } else { Text(store.configured ? "Can't reach server" : "Not configured").font(.callout).foregroundStyle(.secondary) }
        }
    }
}

// MARK: - Settings

struct SettingsView: View {
    var body: some View {
        TabView {
            ServersSettings().tabItem { Label("Servers", systemImage: "server.rack") }
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
        }
        .frame(width: 680, height: 620)
    }
}

struct ServersSettings: View {
    @EnvironmentObject var manager: ServerManager
    @State private var selection: UUID?
    @State private var draft = ServerProfile()
    @State private var apiKey = ""
    @State private var sshPassword = ""
    @State private var delugePassword = ""
    @State private var confirmRemove = false

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 0) {
                List(manager.servers, selection: $selection) { p in
                    Label(p.name, systemImage: "server.rack").tag(p.id)
                }
                HStack(spacing: 4) {
                    Button { let p = manager.addBlank(); selection = p.id } label: { Image(systemName: "plus") }.help("Add a server")
                    Button { confirmRemove = true } label: { Image(systemName: "minus") }.disabled(selection == nil).help("Remove the selected server")
                    Spacer()
                }.buttonStyle(.borderless).padding(8)
            }.frame(width: 180)
            Divider()
            if manager.servers.contains(where: { $0.id == selection }) {
                editor
            } else {
                ContentUnavailableView("No server selected", systemImage: "server.rack", description: Text("Add a server with the + button, or pick one from the list."))
                    .frame(maxWidth: .infinity)
            }
        }
        .onAppear { selection = manager.selectedID ?? manager.servers.first?.id; load() }
        .onChange(of: selection) { _, _ in load() }
        .confirmationDialog("Remove \(draft.name)?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove server", role: .destructive) {
                if let id = selection { manager.remove(id); selection = manager.servers.first?.id }
            }
        } message: { Text("Its saved API key and SSH password are deleted from your Keychain. Nothing changes on the server itself.") }
    }

    var editor: some View {
        let store = selection.flatMap { manager.stores[$0] }
        return Form {
            TextField("Name", text: $draft.name)
            TextField("Server URL", text: $draft.url, prompt: Text("http://192.168.1.10"))
            SecureField("API key", text: $apiKey)
            Toggle("Allow self-signed certificate", isOn: $draft.allowInsecure)
            Text("Create a key in Unraid under Settings, Management Access, API Keys. Viewer is enough to monitor, Admin is needed for controls.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Read temperatures & network over SSH", isOn: $draft.sshEnabled)
            TextField("SSH user", text: $draft.sshUser).disabled(!draft.sshEnabled)
            SecureField("SSH password (optional)", text: $sshPassword).disabled(!draft.sshEnabled)
            Text("Leave the password empty to use your Mac's SSH keys. A password is stored in your Keychain.")
                .font(.caption).foregroundStyle(.secondary)
            TextField("Deluge address (optional)", text: $draft.delugeURL, prompt: Text("Found automatically"))
            SecureField("Deluge Web UI password", text: $delugePassword)
            Text("If this server runs Deluge in Docker, a Deluge tab appears in the sidebar. The address is found automatically (Web UI port 8112 unless Docker publishes another). The Web UI's default password is \"deluge\", which is used when this field is empty.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Save & Connect") { manager.save(draft, apiKey: apiKey, sshPassword: sshPassword, delugePassword: delugePassword) }
                    .keyboardShortcut(.defaultAction).disabled(draft.name.isEmpty)
                if let store {
                    if store.connected { Label("Connected", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.caption) }
                    else if store.configured { Label("Not connected", systemImage: "xmark.circle.fill").foregroundStyle(.red).font(.caption) }
                }
            }
        }.formStyle(.grouped)
    }

    func load() {
        guard let id = selection, let p = manager.servers.first(where: { $0.id == id }) else { return }
        draft = p
        apiKey = manager.stores[id]?.apiKey ?? ""
        sshPassword = manager.stores[id]?.sshPassword ?? ""
        delugePassword = manager.stores[id]?.delugePassword ?? ""
    }
}

struct GeneralSettings: View {
    @AppStorage("refreshSeconds") private var refreshSeconds = 10
    @AppStorage("notifyEnabled") private var notifyEnabled = true
    @AppStorage("diskWarnTemp") private var diskWarnTemp = 45
    @AppStorage("diskCritTemp") private var diskCritTemp = 55
    @AppStorage("cpuWarnTemp") private var cpuWarnTemp = 80
    @AppStorage("hideWindowOnLoginLaunch") private var hideOnLogin = true
    @StateObject private var login = LoginItem()

    var body: some View {
        Form {
            Stepper("Refresh every \(refreshSeconds)s", value: $refreshSeconds, in: 2...300)
            Text("Applies to every server.").font(.caption).foregroundStyle(.secondary)

            Toggle("Launch at login", isOn: Binding(get: { login.isEnabled || login.needsApproval }, set: { login.set($0) }))
            if login.isEnabled || login.needsApproval {
                Toggle("Start in the menu bar only when launched at login", isOn: $hideOnLogin)
            }
            if login.needsApproval {
                HStack {
                    Text("macOS needs your approval: turn Unraid Watcher on in Login Items.").font(.caption).foregroundStyle(.orange)
                    Button("Open Login Items") { login.openSystemSettings() }.controlSize(.small)
                }
            }
            if let e = login.errorText { Text(e).font(.caption).foregroundStyle(.red) }
            if !login.inApplications {
                Text("Tip: move Unraid Watcher to your Applications folder first so the login item keeps working.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Toggle("Notify about alerts", isOn: $notifyEnabled)
            Stepper("Disk warning at \(diskWarnTemp)°C", value: $diskWarnTemp, in: 30...70)
            Stepper("Disk critical at \(diskCritTemp)°C", value: $diskCritTemp, in: 35...80)
            Stepper("CPU warning at \(cpuWarnTemp)°C (needs SSH)", value: $cpuWarnTemp, in: 50...100)
            Text("Alert limits apply to every server. With more than one server, notifications start with the server's name.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Send test notification") {
                requestNotificationPermission()
                postNotification("Unraid Watcher", "Notifications are working.", id: UUID().uuidString)
            }

            Text("Unraid Watcher 1.3.0 · \(copyrightLine)").font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .onAppear { login.refresh() }
    }
}
