// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Ray Munro

import AppKit
import SwiftUI
import Charts

enum Section: String, CaseIterable, Identifiable {
    case overview = "Overview", deluge = "Deluge", system = "System & Power", network = "Network & Temps", performance = "Performance", smart = "SMART Health", controls = "Controls", storage = "Array & Disks", docker = "Docker", vms = "VMs", shares = "Shares", notifications = "Notifications", logs = "Logs"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .overview: "gauge.with.dots.needle.bottom.50percent"
        case .deluge: "arrow.down.arrow.up.circle"
        case .system: "cpu"
        case .network: "network"
        case .performance: "speedometer"
        case .smart: "heart.text.square"
        case .controls: "slider.horizontal.3"
        case .logs: "doc.text.magnifyingglass"
        case .storage: "internaldrive"
        case .docker: "shippingbox"
        case .vms: "desktopcomputer"
        case .shares: "folder.badge.person.crop"
        case .notifications: "bell"
        }
    }
}

struct ServerContentView: View {
    @EnvironmentObject var store: Store
    @State private var selection: Section? = .overview

    var body: some View {
        NavigationSplitView {
            List(Section.allCases.filter { $0 != .deluge || store.delugeAvailable }, id: \.self, selection: $selection) { s in
                Label(s.rawValue, systemImage: s.icon)
                    .badge(s == .notifications ? (store.notificationCounts?.total ?? 0) : 0)
            }
            .safeAreaInset(edge: .top) { ServerPicker().padding(.horizontal, 10).padding(.top, 6).padding(.bottom, 4) }
            .safeAreaInset(edge: .bottom) { BrandFooter() }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
        } detail: {
            VStack(spacing: 0) {
                if let b = store.banner {
                    HStack { Image(systemName: b.isError ? "xmark.octagon.fill" : "checkmark.circle.fill"); Text(b.text).lineLimit(6).textSelection(.enabled); Spacer()
                        Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(b.text, forType: .string) } label: { Image(systemName: "doc.on.doc") }.buttonStyle(.plain).help("Copy message")
                        Button { store.banner = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain) }
                        .padding(10).background((b.isError ? Color.red : Color.green).opacity(0.18)).foregroundStyle(b.isError ? Color.red : Color.green)
                }
                if !store.configured {
                    ContentUnavailableView {
                        Label("Connect to \(store.profile.name)", systemImage: "network")
                    } description: { Text("Open Settings (⌘,) and enter this server's URL and API key.") }
                    .overlay(alignment: .bottom) { SettingsLink { Text("Open Settings") }.padding(.bottom, 40) }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            ErrorsPanel(visible: store.errors.filter { relevant($0.key) })
                            switch selection ?? .overview {
                            case .overview: OverviewView()
                            case .deluge: DelugeView()
                            case .system: SystemView()
                            case .network: NetworkView()
                            case .performance: PerformanceView()
                            case .smart: SmartView()
                            case .controls: ControlsView()
                            case .logs: LogsView()
                            case .storage: StorageView()
                            case .docker: DockerView()
                            case .vms: VMsView()
                            case .shares: SharesView()
                            case .notifications: NotificationsView()
                            }
                        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .toolbar {
                ToolbarItem { Button { Task { await store.refresh() } } label: { Image(systemName: "arrow.clockwise") }.help("Refresh now") }
                ToolbarItem(placement: .status) {
                    if let t = store.lastUpdated { Text("Updated \(t, style: .time)").font(.caption).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle(store.profile.name)
            .navigationSubtitle(store.overview?.info?.os?.hostname ?? "")
        }
    }
    func relevant(_ k: String) -> Bool {
        switch selection ?? .overview {
        case .overview: return ["Overview", "Array", "SSH"].contains(k)
        case .deluge: return false
        case .system: return ["System details", "UPS", "License", "Services", "Flash", "Server"].contains(k)
        case .network, .performance, .logs, .smart: return k == "SSH"
        case .controls: return ["SSH", "Parity status", "Array"].contains(k)
        case .storage: return ["Array", "Disk details", "Parity history", "SSH"].contains(k)
        case .docker: return ["Docker", "Container details", "SSH"].contains(k)
        case .vms: return ["VMs", "SSH"].contains(k)
        case .shares: return ["Shares", "SSH"].contains(k)
        case .notifications: return k == "Notifications"
        }
    }
}

// MARK: - Branding

struct BrandFooter: View {
    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 9) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Unraid Watcher").font(.callout.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                    Text(copyrightLine).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .contentShape(Rectangle()).onTapGesture { showAboutPanel() }
            .help("About Unraid Watcher")
        }.background(.bar)
    }
}

// MARK: - Errors

struct ErrorsPanel: View {
    @EnvironmentObject var store: Store
    let visible: [String: String]
    static let optional: Set<String> = ["License", "Services", "Flash", "Server", "UPS", "Parity status", "Parity history",
                                        "Disk details", "Container details", "System details"]
    @State private var expanded = false

    func copyAll() {
        let text = store.errors.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(separator: "\n")
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
        store.show("Copied \(store.errors.count) error message(s) to the clipboard")
    }

    var body: some View {
        let core = visible.filter { !Self.optional.contains($0.key) }.sorted { $0.key < $1.key }
        let opt = visible.filter { Self.optional.contains($0.key) }.sorted { $0.key < $1.key }
        if !core.isEmpty || !opt.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(core, id: \.key) { k, v in
                    Label("\(k): \(v)", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.callout).textSelection(.enabled)
                }
                if !opt.isEmpty {
                    DisclosureGroup(isExpanded: $expanded) {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(opt, id: \.key) { k, v in Text("\(k): \(v)").font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                        }.padding(.top, 4)
                    } label: {
                        Label("\(opt.count) optional detail\(opt.count == 1 ? "" : "s") unavailable on this server", systemImage: "info.circle").font(.callout).foregroundStyle(.secondary)
                    }
                }
                Button("Copy all errors") { copyAll() }.controlSize(.small)
            }
        }
    }
}

// MARK: - Reusable

struct Card<Content: View>: View {
    let title: String; @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline).foregroundStyle(.secondary)
            content
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct UsageBar: View {
    let fraction: Double
    var body: some View {
        let f = min(max(fraction, 0), 1)
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(f > 0.9 ? Color.red : f > 0.75 ? Color.orange : Color.green).frame(width: g.size.width * f)
            }
        }.frame(height: 8)
    }
}

struct Pill: View {
    let text: String; let color: Color
    var body: some View {
        Text(text).font(.caption.weight(.medium)).padding(.horizontal, 8).padding(.vertical, 2)
            .background(color.opacity(0.18), in: Capsule()).foregroundStyle(color)
    }
}

struct Spark: View {
    let data: [Double]; let color: Color
    var body: some View {
        Chart(Array(data.enumerated()), id: \.offset) { i, v in
            AreaMark(x: .value("t", i), y: .value("v", v)).foregroundStyle(color.opacity(0.2))
            LineMark(x: .value("t", i), y: .value("v", v)).foregroundStyle(color)
        }
        .chartYScale(domain: 0...100).chartXAxis(.hidden).chartYAxis(.hidden).frame(height: 70)
    }
}

func stateColor(_ s: String?) -> Color {
    switch (s ?? "").uppercased() {
    case "STARTED", "RUNNING", "DISK_OK", "ONLINE": .green
    case "PAUSED", "IDLE", "DISK_NP_DSBL", "STARTING": .orange
    case "STOPPED", "SHUTOFF", "EXITED", "DISK_DSBL", "DISK_INVALID": .gray
    default: .secondary
    }
}

// MARK: - Overview

struct OverviewView: View {
    @EnvironmentObject var s: Store
    var body: some View {
        if !s.hotDisks.isEmpty {
            Card(title: "Temperature alerts") {
                ForEach(s.hotDisks, id: \.disk.id) { h in
                    Label("\(h.disk.name ?? "disk") is at \(Int(h.disk.temp ?? 0))°C", systemImage: h.level == 2 ? "flame.fill" : "thermometer.high")
                        .foregroundStyle(h.level == 2 ? .red : .orange)
                }
            }
        }
        let os = s.overview?.info?.os, cpu = s.overview?.info?.cpu
        Card(title: "System") {
            Text("\(os?.hostname ?? "-")").font(.title2.bold())
            Text("\(os?.distro ?? "Unraid") \(os?.release ?? "")").foregroundStyle(.secondary)
            if let c = cpu { Text("\(c.brand ?? "CPU") · \(c.cores ?? 0) cores / \(c.threads ?? 0) threads").font(.callout) }
            if let up = os?.uptime { Text("Booted \(up)").font(.callout).foregroundStyle(.secondary) }
        }
        HStack(alignment: .top, spacing: 16) {
            Card(title: "CPU") {
                Text(String(format: "%.0f%%", s.overview?.metrics?.cpu?.percentTotal ?? 0)).font(.system(size: 34, weight: .bold, design: .rounded))
                Spark(data: s.cpuHistory, color: .blue)
                if let t = s.temps.filter(\.isCPU).map(\.celsius).max() { Text("\(Int(t))°C").font(.caption).foregroundStyle(t > 80 ? .red : .secondary) }
            }
            Card(title: "Memory") {
                let m = s.overview?.metrics?.memory
                Text(String(format: "%.0f%%", m?.percentTotal ?? 0)).font(.system(size: 34, weight: .bold, design: .rounded))
                Spark(data: s.memHistory, color: .purple)
                if let u = m?.used?.value, let t = m?.total?.value { Text("\(bytes(u, unitKB: false)) of \(bytes(t, unitKB: false))").font(.caption).foregroundStyle(.secondary) }
            }
        }
        HStack(alignment: .top, spacing: 16) {
            Card(title: "Array") {
                HStack { Pill(text: s.array?.state ?? "-", color: stateColor(s.array?.state)) }
                if let kb = s.array?.capacity?.kilobytes, let t = kb.total?.value, t > 0 {
                    UsageBar(fraction: (kb.used?.value ?? 0) / t)
                    Text("\(bytes(kb.used?.value ?? 0)) used · \(bytes(kb.free?.value ?? 0)) free").font(.caption).foregroundStyle(.secondary)
                }
                let hot = ((s.array?.disks ?? []) + (s.array?.parities ?? []) + (s.array?.caches ?? [])).compactMap(\.temp).max()
                if let hot { Text("Hottest disk: \(Int(hot))°C").font(.caption).foregroundStyle(hot > 50 ? .red : .secondary) }
            }
            Card(title: "Docker") {
                let r = s.containers.filter(\.isRunning).count
                Text("\(r) / \(s.containers.count)").font(.system(size: 28, weight: .bold, design: .rounded))
                Text("containers running").font(.caption).foregroundStyle(.secondary)
            }
            Card(title: "VMs") {
                let r = s.vms.filter { $0.state?.uppercased() == "RUNNING" }.count
                Text("\(r) / \(s.vms.count)").font(.system(size: 28, weight: .bold, design: .rounded))
                Text("running").font(.caption).foregroundStyle(.secondary)
            }
            Card(title: "Alerts") {
                let n = s.notificationCounts
                Text("\(n?.total ?? 0)").font(.system(size: 28, weight: .bold, design: .rounded))
                Text("\(n?.alert ?? 0) alert · \(n?.warning ?? 0) warning · \(n?.info ?? 0) info").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Storage

struct DiskRow: View {
    @EnvironmentObject var store: Store
    let d: Disk; let role: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(d.name ?? "-").font(.body.weight(.medium))
                Text(d.device ?? "").font(.caption).foregroundStyle(.secondary)
                Pill(text: role, color: .blue)
                Spacer()
                if let t = d.temp { Text("\(Int(t))°C").foregroundStyle(store.tempColor(t)).monospacedDigit() }
                Pill(text: (d.status ?? "-").replacingOccurrences(of: "DISK_", with: ""), color: stateColor(d.status))
            }
            if let size = d.fsSize?.value, size > 0 {
                UsageBar(fraction: (d.fsUsed?.value ?? 0) / size)
                Text("\(bytes(d.fsUsed?.value ?? 0)) of \(bytes(size))").font(.caption).foregroundStyle(.secondary)
                extraLine
            } else if let size = d.size?.value, size > 0 {
                Text(bytes(size, unitKB: false)).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

extension DiskRow {
    @ViewBuilder var extraLine: some View {
        if let x = d.name.flatMap({ store.diskExtras[$0] }) {
            HStack(spacing: 10) {
                if let t = x.fsType { Text(t.uppercased()) }
                if let sp = x.isSpinning { Label(sp ? "Spinning" : "Spun down", systemImage: sp ? "arrow.triangle.2.circlepath" : "moon.zzz") }
                if let r = x.rotational { Text(r ? "HDD" : "SSD") }
                if let r = x.numReads?.value, let w = x.numWrites?.value { Text("R \(Int(r)) · W \(Int(w))") }
                if let e = x.numErrors?.value { Text("\(Int(e)) errors").foregroundStyle(e > 0 ? .red : .secondary) }
            }.font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct SSHNeeded: View {
    @EnvironmentObject var s: Store
    var body: some View {
        Card(title: "Enable SSH") {
            Text("This data is read over SSH. Turn on \"Read temperatures & network over SSH\" in Settings (⌘,) and enter your SSH password (or set up key login).")
            SettingsLink { Text("Open Settings") }
        }
    }
}

struct PerformanceView: View {
    @EnvironmentObject var s: Store
    func kb(_ k: String) -> Double { (s.mem[k] ?? 0) }
    func uptime(_ t: Double) -> String {
        let d = Int(t) / 86400, h = Int(t) % 86400 / 3600, m = Int(t) % 3600 / 60
        return d > 0 ? "\(d)d \(h)h \(m)m" : "\(h)h \(m)m"
    }
    var body: some View {
        if !s.sshEnabled { SSHNeeded() } else {
            Card(title: "Load & uptime") {
                HStack(spacing: 24) {
                    ForEach(Array(zip(["1 min", "5 min", "15 min"], s.load)), id: \.0) { l, v in
                        VStack(alignment: .leading) { Text(String(format: "%.2f", v)).font(.title2.bold().monospacedDigit()); Text(l).font(.caption).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    VStack(alignment: .trailing) { Text(uptime(s.uptimeSeconds)).font(.title3.bold()); Text("uptime").font(.caption).foregroundStyle(.secondary) }
                }
            }
            Card(title: "CPU cores") {
                if s.cores.isEmpty { Text("Collecting a second sample…").foregroundStyle(.secondary) }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 14)], spacing: 10) {
                    ForEach(Array(s.cores.enumerated()), id: \.offset) { i, v in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack { Text("Core \(i)").font(.caption); Spacer(); Text("\(Int(v))%").font(.caption.monospacedDigit()) }
                            UsageBar(fraction: v / 100)
                        }
                    }
                }
            }
            Card(title: "Memory") {
                let total = kb("MemTotal"), avail = kb("MemAvailable")
                let cache = kb("Cached") + kb("Buffers")
                let swapUsed = kb("SwapTotal") - kb("SwapFree")
                if total > 0 {
                    UsageBar(fraction: (total - avail) / total)
                    ForEach([("In use", total - avail - 0), ("Cache & buffers", cache), ("Available", avail), ("Shared (tmpfs)", kb("Shmem")), ("Dirty", kb("Dirty"))], id: \.0) { n, v in
                        HStack { Text(n); Spacer(); Text(bytes(v)).monospacedDigit() }.font(.callout)
                    }
                    if kb("SwapTotal") > 0 { HStack { Text("Swap used"); Spacer(); Text("\(bytes(swapUsed)) of \(bytes(kb("SwapTotal")))") }.font(.callout) }
                } else { Text("Waiting for data…").foregroundStyle(.secondary) }
            }
            Card(title: "Disk I/O") {
                if s.diskIO.isEmpty { Text("Collecting a second sample…").foregroundStyle(.secondary) }
                ForEach(s.diskIO) { d in
                    let name = s.allDisks.first(where: { $0.device == d.dev })?.name
                    HStack {
                        Text(d.dev).font(.body.weight(.medium)); if let n = name { Text(n).font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                        Text("↓ \(rate(d.read))").foregroundStyle(.green); Text("↑ \(rate(d.write))").foregroundStyle(.blue)
                    }.monospacedDigit().font(.callout)
                }
            }
            if !s.fans.isEmpty {
                Card(title: "Fans") {
                    ForEach(s.fans) { f in HStack { Text(f.name); Spacer(); Text("\(Int(f.rpm)) RPM").monospacedDigit() }.font(.callout) }
                }
            }
            Card(title: "Top processes") {
                ForEach(s.procs) { p in
                    HStack { Text(p.name).lineLimit(1); Spacer()
                        Text(String(format: "%.1f%% CPU", p.cpu)).foregroundStyle(.secondary); Text(String(format: "%.1f%% MEM", p.mem)).foregroundStyle(.secondary)
                    }.font(.callout.monospacedDigit())
                }
            }
        }
    }
}

struct LogsView: View {
    @EnvironmentObject var s: Store
    var body: some View {
        if !s.sshEnabled { SSHNeeded() } else {
            Card(title: "System log (last \(s.logLines.count) lines)") {
                if s.logLines.isEmpty { Text("No log data yet").foregroundStyle(.secondary) }
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(s.logLines.enumerated()), id: \.offset) { _, l in
                        let low = l.lowercased()
                        Text(l).font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(low.contains("error") || low.contains("fail") || low.contains("critical") ? Color.red : low.contains("warn") ? .orange : .primary)
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }
}

struct NetworkView: View {
    @EnvironmentObject var s: Store
    var body: some View {
        if !s.sshEnabled {
            Card(title: "Enable SSH") {
                Text("CPU temperatures and network traffic are read over SSH. Turn on \"Read temperatures & network over SSH\" in Settings (⌘,).")
                Text("Needs key-based login. Run once in Terminal:").font(.callout).foregroundStyle(.secondary)
                Text("ssh-copy-id \(s.sshUser)@\(URL(string: s.serverURL.contains("://") ? s.serverURL : "http://" + s.serverURL)?.host ?? "your-server")")
                    .font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                SettingsLink { Text("Open Settings") }
            }
        } else {
            let cpu = s.temps.filter(\.isCPU), other = s.temps.filter { !$0.isCPU }
            Card(title: "CPU temperature") {
                if let m = cpu.map(\.celsius).max() {
                    Text("\(Int(m))°C").font(.system(size: 34, weight: .bold, design: .rounded)).foregroundStyle(m > 80 ? .red : m > 70 ? .orange : .primary)
                    Chart(Array(s.tempHistory.enumerated()), id: \.offset) { i, v in
                        LineMark(x: .value("t", i), y: .value("°C", v)).foregroundStyle(.orange)
                    }.chartXAxis(.hidden).frame(height: 70)
                    ForEach(cpu) { t in HStack { Text(t.label); Spacer(); Text("\(Int(t.celsius))°C").monospacedDigit() }.font(.callout) }
                } else { Text("Waiting for data…").foregroundStyle(.secondary) }
            }
            if !other.isEmpty {
                Card(title: "Other sensors") {
                    ForEach(other) { t in HStack { Text("\(t.chip) · \(t.label)"); Spacer(); Text("\(Int(t.celsius))°C").monospacedDigit() }.font(.callout) }
                }
            }
            Card(title: "Network traffic") {
                HStack(spacing: 24) {
                    Label(rate(s.rxHistory.last ?? 0), systemImage: "arrow.down").foregroundStyle(.green)
                    Label(rate(s.txHistory.last ?? 0), systemImage: "arrow.up").foregroundStyle(.blue)
                }.font(.title3.bold())
                Chart {
                    ForEach(Array(s.rxHistory.enumerated()), id: \.offset) { i, v in
                        LineMark(x: .value("t", i), y: .value("B/s", v), series: .value("d", "Down")).foregroundStyle(.green)
                    }
                    ForEach(Array(s.txHistory.enumerated()), id: \.offset) { i, v in
                        LineMark(x: .value("t", i), y: .value("B/s", v), series: .value("d", "Up")).foregroundStyle(.blue)
                    }
                }.chartXAxis(.hidden).chartForegroundStyleScale(["Down": .green, "Up": .blue]).frame(height: 90)
                Divider()
                ForEach(s.netRates) { r in
                    HStack { Text(r.iface).font(.body.weight(.medium)); Spacer()
                        Text("↓ \(rate(r.rx))").foregroundStyle(.green); Text("↑ \(rate(r.tx))").foregroundStyle(.blue) }.monospacedDigit()
                }
                if s.netRates.isEmpty { Text("Collecting a second sample…").foregroundStyle(.secondary) }
            }
        }
    }
}

struct SystemView: View {
    @EnvironmentObject var s: Store
    func row(_ k: String, _ v: String?) -> some View {
        HStack { Text(k).foregroundStyle(.secondary); Spacer(); Text(v ?? "-").textSelection(.enabled) }
    }
    func join(_ a: String?, _ b: String?) -> String? {
        let t = [a, b].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " "); return t.isEmpty ? nil : t
    }
    var body: some View {
        let i = s.details?.info
        Card(title: "Hardware") {
            row("System", join(i?.system?.manufacturer, i?.system?.model))
            row("Motherboard", join(i?.baseboard?.manufacturer, i?.baseboard?.model))
            row("CPU", join(s.overview?.info?.cpu?.brand, nil))
            row("CPU socket", i?.cpu?.socket)
            if let sp = i?.cpu?.speed?.value, sp > 0 { row("CPU speed", String(format: "%.2f GHz", sp)) }
            row("Architecture", i?.os?.arch)
        }
        Card(title: "Software") {
            row("Unraid", i?.versions?.core?.unraid ?? s.overview?.info?.os?.release)
            row("Kernel", i?.versions?.core?.kernel ?? i?.os?.kernel)
            row("API", i?.versions?.core?.api)
            row("Platform", i?.os?.platform)
        }
        Card(title: "License & server") {
            row("Licence", join(s.registration?.type?.s, s.registration?.state?.s))
            row("Expires", s.registration?.expiration?.s)
            row("Flash drive", join(s.flash?.vendor?.s, s.flash?.product?.s))
            row("Time zone", s.serverVars?.timeZone?.s)
            row("Array disks", s.serverVars?.mdNumDisks?.s)
            row("Shares", s.serverVars?.shareCount?.s)
            row("Safe mode", s.serverVars?.safeMode?.s)
        }
        if !s.services.isEmpty {
            Card(title: "Services") {
                ForEach(s.services) { sv in
                    HStack { Text(sv.name ?? "-"); if let v = sv.version?.s { Text(v).font(.caption).foregroundStyle(.secondary) }
                        Spacer(); Pill(text: sv.online == true ? "Online" : "Offline", color: sv.online == true ? .green : .gray) }
                }
            }
        }
        Card(title: "UPS") {
            if s.upsDevices.isEmpty { Text("No UPS detected").foregroundStyle(.secondary) }
            ForEach(s.upsDevices) { u in
                HStack { Text(u.name ?? u.model ?? u.id).font(.body.weight(.medium)); Spacer(); Pill(text: u.status ?? "-", color: stateColor(u.status)) }
                if let c = u.battery?.chargeLevel { Text("Battery \(Int(c))%"); UsageBar(fraction: 1 - c / 100) }
                if let r = u.battery?.estimatedRuntime { Text("Runtime \(Int(r / 60)) min").font(.caption).foregroundStyle(.secondary) }
                if let l = u.power?.loadPercentage { Text("Load \(Int(l))%").font(.caption).foregroundStyle(.secondary) }
                if let v = u.power?.inputVoltage { Text("Input \(Int(v)) V").font(.caption).foregroundStyle(.secondary) }
            }
        }
    }
}

struct StorageView: View {
    @EnvironmentObject var s: Store
    var body: some View {
        Card(title: "Array - \(s.array?.state ?? "unknown")") {
            if let kb = s.array?.capacity?.kilobytes, let t = kb.total?.value, t > 0 {
                UsageBar(fraction: (kb.used?.value ?? 0) / t)
                Text("\(bytes(kb.used?.value ?? 0)) used of \(bytes(t))").font(.callout)
            }
            ForEach(s.array?.parities ?? []) { DiskRow(d: $0, role: "Parity"); Divider() }
            ForEach(s.array?.disks ?? []) { DiskRow(d: $0, role: "Data"); Divider() }
        }
        if let c = s.array?.caches, !c.isEmpty {
            Card(title: "Cache") { ForEach(c) { DiskRow(d: $0, role: "Cache"); Divider() } }
        }
        if !s.mounts.isEmpty {
            Card(title: "Mounted filesystems") {
                ForEach(s.mounts) { m in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack { Text(m.path).font(.body.weight(.medium)); Text(m.type).font(.caption).foregroundStyle(.secondary); Spacer()
                            Text("\(bytes(m.used)) of \(bytes(m.size))").font(.caption).foregroundStyle(.secondary) }
                        UsageBar(fraction: m.used / m.size)
                    }
                    Divider()
                }
            }
        }
        Card(title: "Parity check history") {
            if s.parityHistory.isEmpty { Text("No history").foregroundStyle(.secondary) }
            ForEach(s.parityHistory.prefix(10)) { p in
                HStack {
                    Text(p.date ?? "-")
                    Spacer()
                    if let d = p.duration?.value { Text("\(Int(d / 3600))h \(Int(d.truncatingRemainder(dividingBy: 3600) / 60))m").foregroundStyle(.secondary) }
                    if let sp = p.speed { Text("\(sp) MB/s").foregroundStyle(.secondary) }
                    Pill(text: "\(Int(p.errors?.value ?? 0)) errors", color: (p.errors?.value ?? 0) > 0 ? .red : .green)
                }.font(.callout)
                Divider()
            }
        }
    }
}

// MARK: - Docker / VMs / Shares / Notifications

struct DockerView: View {
    @EnvironmentObject var s: Store
    @State private var confirmStop: Container?
    @State private var logTarget: Container?
    var body: some View {
        Card(title: "Containers (\(s.containers.count))") {
            ForEach(s.containers) { c in
                HStack {
                    Circle().fill(c.isRunning ? .green : c.state?.uppercased() == "PAUSED" ? .orange : .gray).frame(width: 9, height: 9)
                    VStack(alignment: .leading) {
                        Text(c.displayName).font(.body.weight(.medium))
                        Text(c.image ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        if let x = s.containerExtras[c.id] {
                            let ports = Set((x.ports ?? []).compactMap { p in p.publicPort.map { "\($0)→\(p.privatePort ?? 0)" } }).sorted()
                            HStack(spacing: 8) {
                                if x.autoStart == true { Label("Auto-start", systemImage: "bolt.fill") }
                                if !ports.isEmpty { Text(ports.joined(separator: ", ")) }
                                if let t = x.created?.value, t > 0 { Text("Created \(Date(timeIntervalSince1970: t).formatted(date: .abbreviated, time: .omitted))") }
                            }.font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                    Spacer()
                    Text(c.status ?? c.state ?? "").font(.caption).foregroundStyle(.secondary)
                    if s.busyContainers.contains(c.id) {
                        ProgressView().controlSize(.small).frame(width: 60)
                    } else {
                        let paused = c.state?.uppercased() == "PAUSED"
                        if c.isRunning || paused {
                            Button { confirmStop = c } label: { Image(systemName: "stop.fill") }.help("Stop \(c.displayName)")
                        } else {
                            Button { Task { await s.containerAction(c, "start") } } label: { Image(systemName: "play.fill") }.help("Start \(c.displayName)")
                        }
                        Menu {
                            if c.isRunning { Button("Restart") { Task { await s.containerAction(c, "restart") } } }
                            if c.isRunning { Button("Pause") { Task { await s.containerAction(c, "pause") } } }
                            if paused { Button("Resume") { Task { await s.containerAction(c, "unpause") } } }
                            Button("View logs…") { logTarget = c }.disabled(!s.sshEnabled)
                        } label: { Image(systemName: "ellipsis.circle") }
                        .menuStyle(.borderlessButton).frame(width: 28)
                    }
                }
                Divider()
            }
        }
        .confirmationDialog("Stop \(confirmStop?.displayName ?? "container")?", isPresented: Binding(
            get: { confirmStop != nil }, set: { if !$0 { confirmStop = nil } }), titleVisibility: .visible) {
            Button("Stop", role: .destructive) { if let c = confirmStop { Task { await s.containerAction(c, "stop") } } }
        }
        .sheet(item: $logTarget) { c in ContainerLogSheet(container: c) }
    }
}

struct ContainerLogSheet: View {
    @EnvironmentObject var s: Store
    @Environment(\.dismiss) private var dismiss
    let container: Container
    @State private var text = "Loading…"
    var body: some View {
        VStack(alignment: .leading) {
            HStack { Text("\(container.displayName) logs").font(.headline); Spacer()
                Button("Refresh") { Task { text = await s.containerLogs(container) } }
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction) }
            ScrollView { Text(text).font(.system(size: 11, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                .padding(8).background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
        }.padding().frame(width: 760, height: 520)
        .task { text = await s.containerLogs(container) }
    }
}

struct VMsView: View {
    @EnvironmentObject var s: Store
    @State private var confirm: (vm: VM, verb: String, label: String)?
    @State private var detail: VM?
    @State private var editVM: VM?
    @State private var creating = false
    @State private var cloneVM: VM?
    var body: some View {
        HStack { Spacer(); Button("New VM…") { creating = true }.disabled(!s.sshEnabled) }
        Card(title: "Virtual Machines (\(s.vms.count))") {
            if s.vms.isEmpty { Text("No VMs").foregroundStyle(.secondary) }
            ForEach(s.vms) { v in
                let st = (v.state ?? "").uppercased()
                HStack {
                    Text(v.name ?? v.id).font(.body.weight(.medium)); Spacer()
                    Pill(text: v.state ?? "-", color: stateColor(v.state))
                    Menu {
                        Button("Details…") { detail = v }.disabled(!s.sshEnabled)
                        Button("Edit…") { editVM = v }.disabled(!s.sshEnabled)
                        Button("Clone…") { cloneVM = v }.disabled(!s.sshEnabled || !(st == "SHUTOFF" || st == "STOPPED"))
                        Button("Eject install media") { Task { await s.ejectMedia(v.name ?? v.id) } }.disabled(!s.sshEnabled)
                        if st == "RUNNING" || st == "PAUSED" {
                            Button("Open console (Screen Sharing)") { Task { await s.openConsole(v.name ?? v.id, browser: false) } }.disabled(!s.sshEnabled)
                            Button("Open console in browser") { Task { await s.openConsole(v.name ?? v.id, browser: true) } }.disabled(!s.sshEnabled)
                        }
                        Divider()
                        if st == "SHUTOFF" || st == "STOPPED" || st == "CRASHED" { Button("Start") { Task { await s.vmAction(v, "start", label: "Starting") } } }
                        if st == "RUNNING" {
                            Button("Shut down") { Task { await s.vmAction(v, "stop", label: "Shutting down") } }
                            Button("Pause") { Task { await s.vmAction(v, "pause", label: "Paused") } }
                            Button("Reboot") { confirm = (v, "reboot", "Rebooting") }
                            Button("Force stop", role: .destructive) { confirm = (v, "forceStop", "Force-stopped") }
                        }
                        if st == "PAUSED" || st == "PMSUSPENDED" { Button("Resume") { Task { await s.vmAction(v, "resume", label: "Resumed") } } }
                    } label: { Image(systemName: "ellipsis.circle") }.menuStyle(.borderlessButton).frame(width: 28)
                }
                Divider()
            }
        }
        .sheet(item: $detail) { VMDetailSheet(vm: $0) }
        .sheet(item: $editVM) { VMEditSheet(vm: $0) }
        .sheet(isPresented: $creating) { VMCreateSheet() }
        .sheet(item: $cloneVM) { VMCloneSheet(vm: $0) }
        .confirmationDialog("\(confirm?.verb == "forceStop" ? "Force stop" : "Reboot") \(confirm?.vm.name ?? "VM")?", isPresented: Binding(
            get: { confirm != nil }, set: { if !$0 { confirm = nil } }), titleVisibility: .visible) {
            Button(confirm?.verb == "forceStop" ? "Force stop (like pulling the plug)" : "Reboot", role: .destructive) {
                if let c = confirm { Task { await s.vmAction(c.vm, c.verb, label: c.label) } }
            }
        }
    }
}

struct NotificationsView: View {
    @EnvironmentObject var s: Store
    var body: some View {
        Card(title: "Unread notifications (\(s.notificationCounts?.total ?? s.notifications.count))") {
            if s.notifications.isEmpty { Text("All clear 🎉").foregroundStyle(.secondary) }
            else { Button("Archive all") { Task { await s.archiveAll() } } }
            ForEach(s.notifications) { n in
                HStack(alignment: .top) {
                    Image(systemName: n.importance?.uppercased() == "ALERT" ? "xmark.octagon.fill" : n.importance?.uppercased() == "WARNING" ? "exclamationmark.triangle.fill" : "info.circle.fill")
                        .foregroundStyle(n.importance?.uppercased() == "ALERT" ? .red : n.importance?.uppercased() == "WARNING" ? .orange : .blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(n.subject ?? n.title ?? "").font(.body.weight(.medium))
                        if let d = n.description { Text(d).font(.callout).foregroundStyle(.secondary) }
                        if let t = n.timestamp { Text(t).font(.caption).foregroundStyle(.tertiary) }
                    }
                    Spacer()
                    Button { Task { await s.archive(n) } } label: { Image(systemName: "archivebox") }.help("Archive")
                }
                Divider()
            }
        }
    }
}

// MARK: - Menu bar & settings

// MARK: - SMART

struct SmartView: View {
    @EnvironmentObject var s: Store
    @State private var confirmTest: (dev: String, kind: String)?
    func fmt(_ v: Double?) -> String { v.map { String(Int($0)) } ?? "-" }
    var body: some View {
        if !s.sshEnabled { SSHNeeded() } else {
            HStack {
                Text(s.lastSmart.map { "Checked \($0.formatted(date: .omitted, time: .shortened)) - spun-down disks are skipped so they stay asleep" } ?? "Not checked yet")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                if s.smartLoading { ProgressView().controlSize(.small) }
                Button("Check now") { Task { await s.loadSMART() } }.disabled(s.smartLoading)
            }
            ForEach(s.allDisks) { d in
                if let dev = d.device {
                    let i = s.smart[dev]
                    Card(title: "\(d.name ?? dev) · \(dev)") {
                        HStack {
                            Pill(text: (i?.health ?? .unknown).rawValue, color: (i?.health ?? .unknown).color)
                            if i?.standby == true { Pill(text: "Spun down", color: .secondary) }
                            Spacer()
                            if let t = i?.temp ?? d.temp { Text("\(Int(t))°C").foregroundStyle(s.tempColor(t)).monospacedDigit() }
                        }
                        if let i {
                            ForEach(i.concerns, id: \.self) { Label($0, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.callout) }
                            Group {
                                kv("Model", i.model); kv("Serial", i.serial); kv("Firmware", i.firmware)
                                kv("Capacity", i.capacity.map { bytes($0, unitKB: false) })
                                kv("Type", i.rotation.map { $0 == 0 ? "SSD" : "\($0) RPM" })
                                kv("Power-on", i.hours.map { "\(Int($0)) h (\(Int($0 / 24)) days)" })
                                kv("Power cycles", i.cycles.map { String(Int($0)) })
                                kv("Self-test", i.selfTest); kv("Error log entries", i.errorCount.map { String(Int($0)) })
                            }
                            if !i.nvme.isEmpty { ForEach(i.nvme) { kv($0.k, $0.v) } }
                            if !i.attrs.isEmpty {
                                DisclosureGroup("SMART attributes (\(i.attrs.count))") {
                                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                                        GridRow { Text("ID"); Text("Name"); Text("Value"); Text("Worst"); Text("Thresh"); Text("Raw") }.font(.caption.bold())
                                        ForEach(i.attrs) { a in
                                            GridRow {
                                                Text("\(a.id)"); Text(a.name); Text("\(a.value)"); Text("\(a.worst)"); Text("\(a.thresh)"); Text(a.raw)
                                            }.font(.caption.monospacedDigit()).foregroundStyle(a.failed ? .red : .primary)
                                        }
                                    }.padding(.top, 6)
                                }
                            }
                            HStack {
                                Button("Short self-test") { Task { await s.selfTest(dev, kind: "short") } }
                                Button("Extended self-test") { confirmTest = (dev, "long") }
                                Spacer()
                                Button("Spin down") { Task { await s.spin([dev], up: false) } }
                                Button("Spin up") { Task { await s.spin([dev], up: true) } }
                            }.controlSize(.small)
                        } else { Text(s.smartLoading ? "Reading…" : "No SMART data yet").foregroundStyle(.secondary) }
                    }
                }
            }
            .confirmationDialog("Start an extended self-test on \(confirmTest?.dev ?? "")?", isPresented: Binding(
                get: { confirmTest != nil }, set: { if !$0 { confirmTest = nil } }), titleVisibility: .visible) {
                Button("Start (can take hours)") { if let c = confirmTest { Task { await s.selfTest(c.dev, kind: c.kind) } } }
            } message: { Text("The disk stays usable but will be slower, and a spun-down disk will wake up.") }
        }
    }
    @ViewBuilder func kv(_ k: String, _ v: String?) -> some View {
        if let v, !v.isEmpty { HStack { Text(k).foregroundStyle(.secondary); Spacer(); Text(v).textSelection(.enabled) }.font(.callout) }
    }
}

// MARK: - Controls

struct ControlsView: View {
    @EnvironmentObject var s: Store
    enum Confirm: String, Identifiable { case stopArray, parityCorrect, reboot, shutdown, spinDownAll; var id: String { rawValue } }
    @State private var confirm: Confirm?
    @State private var command = ""
    @State private var history: [String] = []

    var body: some View {
        let state = (s.array?.state ?? "").uppercased()
        Card(title: "Array") {
            HStack {
                Pill(text: s.array?.state ?? "-", color: stateColor(s.array?.state))
                Spacer()
                if state == "STARTED" { Button("Stop array…", role: .destructive) { confirm = .stopArray } }
                else { Button("Start array") { Task { await s.setArray(start: true) } } }
            }
            Divider()
            if let p = s.parityStatus, p.running == true {
                HStack { Text("Parity check \(p.paused == true ? "paused" : "running")"); Spacer()
                    Text("\(Int(p.progress?.value ?? 0))%  ·  \(Int(p.errors?.value ?? 0)) errors").monospacedDigit() }
                UsageBar(fraction: (p.progress?.value ?? 0) / 100)
                HStack {
                    if p.paused == true { Button("Resume") { Task { await s.parity("resume") } } }
                    else { Button("Pause") { Task { await s.parity("pause") } } }
                    Button("Cancel check", role: .destructive) { Task { await s.parity("cancel") } }
                }
            } else {
                HStack {
                    Text("Parity check").foregroundStyle(.secondary); Spacer()
                    Button("Start (read-only)") { Task { await s.startParity(correcting: false) } }.disabled(state != "STARTED")
                    Button("Start (correct errors)…") { confirm = .parityCorrect }.disabled(state != "STARTED")
                }
            }
        }
        Card(title: "Disks & mover (needs SSH)") {
            HStack {
                Text("Spin all disks").foregroundStyle(.secondary); Spacer()
                Button("Spin up") { Task { await s.spin(s.allDisks.compactMap(\.device), up: true) } }
                Button("Spin down…") { confirm = .spinDownAll }
            }
            HStack {
                Text("Mover (cache → array)").foregroundStyle(.secondary); Spacer()
                Button("Start") { Task { await s.mover("start") } }
                Button("Stop") { Task { await s.mover("stop") } }
            }
        }.disabled(!s.sshEnabled)
        Card(title: "Power (needs SSH)") {
            HStack {
                Text("Cleanly stops the array first, like the web UI's buttons. A shut-down server can't be turned back on from here.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Reboot…", role: .destructive) { confirm = .reboot }
                Button("Shut down…", role: .destructive) { confirm = .shutdown }
            }
        }.disabled(!s.sshEnabled)
        Card(title: "Console (needs SSH)") {
            HStack {
                TextField("Command to run as \(s.sshUser) on the server", text: $command).textFieldStyle(.roundedBorder).font(.system(.body, design: .monospaced))
                    .onSubmit(run)
                Button("Run", action: run).disabled(command.trimmingCharacters(in: .whitespaces).isEmpty || s.consoleRunning)
                if s.consoleRunning { ProgressView().controlSize(.small) }
            }
            if !history.isEmpty {
                ScrollView(.horizontal) { HStack { ForEach(history, id: \.self) { h in Button(h) { command = h }.buttonStyle(.link).font(.caption.monospaced()) } } }
            }
            if !s.consoleOutput.isEmpty {
                ScrollView { Text(s.consoleOutput).font(.system(size: 11, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                    .frame(maxHeight: 280).padding(8).background(.background, in: RoundedRectangle(cornerRadius: 8))
            }
        }.disabled(!s.sshEnabled)
        if !s.sshEnabled { SSHNeeded() }
        EmptyView()
            .confirmationDialog(title, isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }), titleVisibility: .visible) {
                Button(confirmLabel, role: .destructive) { perform() }
            } message: { Text(message) }
    }

    func run() {
        let c = command.trimmingCharacters(in: .whitespaces)
        guard !c.isEmpty else { return }
        history = Array(([c] + history.filter { $0 != c }).prefix(8))
        Task { await s.runConsole(c) }
    }
    var title: String {
        switch confirm {
        case .stopArray: "Stop the array on \(s.profile.name)?"; case .parityCorrect: "Start a correcting parity check on \(s.profile.name)?"
        case .reboot: "Reboot \(s.profile.name)?"; case .shutdown: "Shut down \(s.profile.name)?"
        case .spinDownAll: "Spin down all disks on \(s.profile.name)?"; case nil: ""
        }
    }
    var message: String {
        switch confirm {
        case .stopArray: "Shares, Docker containers and VMs will become unavailable until the array is started again."
        case .parityCorrect: "Parity will be rewritten to match the data disks. Only do this if you trust the data disks."
        case .reboot: "All services will go down briefly."
        case .shutdown: "The server will power off and can't be restarted from this app."
        case .spinDownAll: "Disks that are in use will spin up again on next access."
        case nil: ""
        }
    }
    var confirmLabel: String {
        switch confirm { case .stopArray: "Stop array"; case .parityCorrect: "Start"; case .reboot: "Reboot"; case .shutdown: "Shut down"; case .spinDownAll: "Spin down"; case nil: "OK" }
    }
    func perform() {
        guard let c = confirm else { return }
        Task {
            switch c {
            case .stopArray: await s.setArray(start: false)
            case .parityCorrect: await s.startParity(correcting: true)
            case .reboot: await s.power(reboot: true)
            case .shutdown: await s.power(reboot: false)
            case .spinDownAll: await s.spin(s.allDisks.compactMap(\.device), up: false)
            }
        }
    }
}
